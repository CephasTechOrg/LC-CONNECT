import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../constants/app_constants.dart';
import 'ws_protocol.dart';

enum RealtimeStatus { disconnected, connecting, authenticating, ready, reconnecting }

/// Full-jitter exponential backoff, capped. Pure → unit-testable.
Duration backoffDelay(int attempt, Random random, {int baseMs = 500, int capMs = 30000}) {
  final exp = baseMs * (1 << attempt.clamp(0, 16));
  final ceiling = min(capMs, exp);
  return Duration(milliseconds: random.nextInt(ceiling + 1));
}

/// A random v4 UUID without a package dependency.
String uuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Owns exactly one authenticated WebSocket. Reconnects with backoff+jitter,
/// restores subscriptions, and republishes inbound events on a broadcast stream.
class RealtimeClient {
  static const _forbiddenCloseCode = 4403; // suspended/unverified — do not retry

  final Uri url;
  final Future<String?> Function() tokenProvider;
  final Random _random;

  static const _maxOutbox = 50;

  final _status = ValueNotifier<RealtimeStatus>(RealtimeStatus.disconnected);
  final _events = StreamController<InboundEvent>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  final _subscriptions = <String>{};
  final _outbox = <Map<String, dynamic>>[]; // message.send frames buffered until ready

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _hadConnection = false;
  bool _disposed = false;

  RealtimeClient({required this.url, required this.tokenProvider, Random? random})
      : _random = random ?? Random();

  ValueListenable<RealtimeStatus> get status => _status;
  Stream<InboundEvent> get events => _events.stream;

  /// Fires when the socket returns to `ready` after a drop — cue to REST-sync.
  Stream<void> get reconnected => _reconnected.stream;

  Future<void> connect() async {
    if (_disposed) return;
    final s = _status.value;
    if (s == RealtimeStatus.connecting || s == RealtimeStatus.authenticating || s == RealtimeStatus.ready) {
      return;
    }
    await _open();
  }

  Future<void> _open() async {
    if (_disposed) return;
    _cancelReconnect();
    final token = await tokenProvider();
    if (token == null) {
      _scheduleReconnect(); // no session yet — try again shortly
      return;
    }
    _status.value = RealtimeStatus.connecting;
    final channel = WebSocketChannel.connect(url);
    try {
      await channel.ready;
    } catch (_) {
      _status.value = RealtimeStatus.disconnected;
      _scheduleReconnect();
      return;
    }
    if (_disposed) {
      await channel.sink.close();
      return;
    }
    _channel = channel;
    _status.value = RealtimeStatus.authenticating;
    _sub = channel.stream.listen(_onData, onError: (_) => _onClosed(), onDone: _onClosed, cancelOnError: true);
    _sink(authFrame(token));
  }

  void _onData(dynamic data) {
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (kDebugMode) {
      if (raw['type'] == 'error') {
        debugPrint('WS<- error code=${raw['code']} msg=${raw['message']}');
      } else {
        debugPrint('WS<- ${raw['type']} conv=${raw['conversation_id']}');
      }
    }
    final event = parseInbound(raw);
    if (event is AuthOk) {
      _attempt = 0;
      final wasReconnect = _hadConnection;
      _hadConnection = true;
      _status.value = RealtimeStatus.ready;
      for (final conversationId in _subscriptions) {
        _sink(subscribeFrame(uuidV4(_random), conversationId));
      }
      // Flush any sends composed before the socket was ready (idempotent on the
      // server via client_message_id, so re-flushing after a reconnect is safe).
      final pending = List.of(_outbox);
      _outbox.clear();
      for (final frame in pending) {
        _sink(frame);
      }
      if (wasReconnect) _reconnected.add(null);
      return;
    }
    _events.add(event);
  }

  void _onClosed() {
    final code = _channel?.closeCode;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (_disposed) return;
    if (code == _forbiddenCloseCode) {
      _status.value = RealtimeStatus.disconnected; // account not permitted — stop
      return;
    }
    _status.value = RealtimeStatus.reconnecting;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _cancelReconnect();
    final delay = backoffDelay(_attempt, _random);
    _attempt++;
    _reconnectTimer = Timer(delay, _open);
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ── subscriptions + sends ───────────────────────────────────────────────────

  void subscribe(String conversationId) {
    _subscriptions.add(conversationId);
    if (_status.value == RealtimeStatus.ready) {
      _sink(subscribeFrame(uuidV4(_random), conversationId));
    }
  }

  void unsubscribe(String conversationId) {
    _subscriptions.remove(conversationId);
    if (_status.value == RealtimeStatus.ready) _sink(unsubscribeFrame(conversationId));
  }

  void sendMessage({required String conversationId, required String clientMessageId, required String body}) {
    final frame = sendFrame(requestId: uuidV4(_random), conversationId: conversationId, clientMessageId: clientMessageId, body: body);
    if (_status.value == RealtimeStatus.ready) {
      _sink(frame);
    } else if (_outbox.length < _maxOutbox) {
      _outbox.add(frame); // flushed on next auth.ok
    }
  }

  void sendTyping(String conversationId, {required bool active}) => _sink(typingFrame(conversationId, active: active));

  void markRead(String conversationId, String throughMessageId) => _sink(readFrame(conversationId, throughMessageId));

  void _sink(Map<String, dynamic> frame) {
    if (_status.value == RealtimeStatus.ready || frame['type'] == 'auth') {
      if (kDebugMode && frame['type'] != 'auth') {
        debugPrint('WS-> ${frame['type']} conv=${frame['conversation_id']}');
      }
      _channel?.sink.add(jsonEncode(frame));
    }
  }

  /// On logout: drop the socket and forget subscriptions + queued sends.
  void clear() {
    _subscriptions.clear();
    _outbox.clear();
    _teardown();
  }

  void _teardown() {
    _cancelReconnect();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _hadConnection = false;
    if (!_disposed) _status.value = RealtimeStatus.disconnected;
  }

  void dispose() {
    _disposed = true;
    _teardown();
    _events.close();
    _reconnected.close();
    _status.dispose();
  }
}

Uri _wsUrl() {
  // http://host/api/v1 → ws://host/api/v1/ws ; https → wss
  final ws = AppConstants.apiBaseUrl.replaceFirst('http', 'ws');
  return Uri.parse('$ws/ws');
}

/// Singleton client tied to auth: connects when signed in, clears on sign-out.
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(
    url: _wsUrl(),
    tokenProvider: () async => Supabase.instance.client.auth.currentSession?.accessToken,
  );
  ref.listen<AsyncValue<AuthUser?>>(authNotifierProvider, (_, next) {
    if (next.asData?.value != null) {
      client.connect();
    } else {
      client.clear();
    }
  }, fireImmediately: true);
  ref.onDispose(client.dispose);
  return client;
});

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

  /// Seam for tests: the real connector hits the network, which makes every timing behaviour
  /// here (heartbeat, watchdog, backoff) otherwise unverifiable.
  final WebSocketChannel Function(Uri) connectChannel;

  /// Cap on the opening handshake. Render's free tier spins down when idle, so a cold start can
  /// hang the handshake for a long time; without a cap the client sits in `connecting`, where
  /// `connect()` early-returns and every send silently lands in the outbox.
  final Duration connectTimeout;

  /// Reconnect after this many heartbeat intervals with no inbound frame. Two tolerates one
  /// lost ping; the resulting ~3-interval detection (75s at the default 25s) still lands inside
  /// the server's 90s idle reaper.
  static const _maxSilentIntervals = 2;

  static const maxOutboxSize = 50;
  /// Warn the UI when the offline send queue is nearly full.
  static const outboxWarnThreshold = 40;

  final _status = ValueNotifier<RealtimeStatus>(RealtimeStatus.disconnected);
  final _outboxCount = ValueNotifier<int>(0);
  final _events = StreamController<InboundEvent>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  final _subscriptions = <String>{};
  final _outbox = <Map<String, dynamic>>[]; // message.send frames buffered until ready

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _attempt = 0;
  bool _hadConnection = false;
  bool _disposed = false;

  /// Server-advertised keepalive interval, from `auth.ok`.
  Duration _heartbeat = const Duration(seconds: 25);

  /// The protocol version the *server* advertised on the last `auth.ok`.
  ///
  /// The client's own [kProtocolVersion] says what it can speak; this says what the peer
  /// understands, and during a staged rollout those differ. A new client reaches TestFlight
  /// before — or alongside — the API deploy, and sending a frame the server has never heard of
  /// is not free: it answers `unsupported_frame`, and before the gateway told that apart from a
  /// malformed frame it spent the abuse budget and closed with 4429, which the client retries,
  /// which bans it again. Gate new frames on [supportsProtocol] instead of hoping.
  ///
  /// Only read through [serverProtocolVersion], which reports zero unless the socket is `ready`
  /// — there are two ways to lose a socket (`_onClosed` on a drop, `_teardown` on suspend and
  /// logout) and a negotiated version that outlived either would gate a new frame open against
  /// a server that never agreed to it. Deriving it from readiness leaves no reset to forget.
  int _negotiatedProtocolVersion = 0;

  /// Heartbeat intervals elapsed with no inbound frame at all. Counting ticks rather than
  /// comparing timestamps keeps this independent of the wall clock.
  int _silentIntervals = 0;

  /// `message.send` frames written to a *ready* socket but not yet acked, keyed by request id.
  /// A write to a half-open socket succeeds silently, so without this they would be lost with
  /// no error at all — the "sometimes a message just fails" case. Re-queued on disconnect.
  final _inflight = <String, Map<String, dynamic>>{};
  final _requestToClientId = <String, String>{};

  RealtimeClient({
    required this.url,
    required this.tokenProvider,
    Random? random,
    WebSocketChannel Function(Uri)? connectChannel,
    this.connectTimeout = const Duration(seconds: 30),
  })  : _random = random ?? Random(),
        connectChannel = connectChannel ?? WebSocketChannel.connect;

  ValueListenable<RealtimeStatus> get status => _status;

  /// Queued `message.send` frames waiting for the socket to reach `ready`.
  ValueListenable<int> get outboxCount => _outboxCount;

  /// What the connected server understands — see [_negotiatedProtocolVersion].
  ///
  /// Zero unless a socket is up and authenticated: nothing has been negotiated, so nothing is
  /// supported. Zero rather than [kProtocolVersion], because assuming the peer speaks whatever
  /// this build speaks is the mistake.
  int get serverProtocolVersion =>
      _status.value == RealtimeStatus.ready ? _negotiatedProtocolVersion : 0;

  /// Whether the connected server understands frames introduced in protocol [version].
  ///
  /// Every frame added after v1 must be gated on this, so an unsupported feature degrades to
  /// "not on this connection" rather than being written into a void.
  bool supportsProtocol(int version) => serverProtocolVersion >= version;

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
    if (_disposed) return; // disposed during the token await — the notifier is gone
    _status.value = RealtimeStatus.connecting;
    final channel = connectChannel(url);
    try {
      await channel.ready.timeout(connectTimeout);
    } catch (_) {
      unawaited(channel.sink.close());
      if (_disposed) return; // disposed while the handshake was still pending
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
    // Any inbound byte proves the socket is still two-way; the keepalive reads this.
    _silentIntervals = 0;
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (kDebugMode && raw['type'] == 'error') {
      debugPrint('WS<- error code=${raw['code']} msg=${raw['message']}');
    }
    final event = parseInbound(raw);
    if (event is AuthOk) {
      _attempt = 0;
      final wasReconnect = _hadConnection;
      _hadConnection = true;
      _status.value = RealtimeStatus.ready;
      _negotiatedProtocolVersion = event.protocolVersion;
      _startHeartbeat(event.heartbeatSeconds);
      for (final conversationId in _subscriptions) {
        _sink(subscribeFrame(uuidV4(_random), conversationId));
      }
      // Flush any sends composed before the socket was ready (idempotent on the
      // server via client_message_id, so re-flushing after a reconnect is safe).
      final pending = List.of(_outbox);
      _outbox.clear();
      _syncOutboxCount();
      for (final frame in pending) {
        _sink(frame);
      }
      if (wasReconnect) _reconnected.add(null);
      return;
    }
    if (event is Pong) return; // liveness only — already stamped above
    if (event is MessageAck) _clearInflightFor(event.clientMessageId);
    if (event is WsError && event.requestId != null) _forgetRequest(event.requestId!);
    _events.add(event);
  }

  // ── keepalive ───────────────────────────────────────────────────────────────

  /// The server reaps sockets idle beyond `WS_IDLE_TIMEOUT_SECONDS`, and only *inbound
  /// application frames* refresh its clock. A chat left open without typing therefore dies
  /// silently, which is why messages stopped arriving until the screen was reopened.
  void _startHeartbeat(int seconds) {
    _heartbeat = Duration(seconds: seconds.clamp(5, 300));
    _silentIntervals = 0;
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_heartbeat, (_) {
      // Two whole intervals without a single inbound frame means the socket is half-open:
      // writes still report success but nothing is arriving. A stalled read is the only
      // detectable symptom, so treat it as a disconnect and reconnect rather than sit there
      // looking healthy while messages silently fail.
      if (_silentIntervals >= _maxSilentIntervals) {
        _teardown(keepConnectionFlag: true);
        _scheduleReconnect();
        return;
      }
      _silentIntervals++;
      _sink(pingFrame());
    });
  }

  void _stopHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _silentIntervals = 0;
  }

  // ── in-flight sends ─────────────────────────────────────────────────────────

  void _clearInflightFor(String? clientMessageId) {
    if (clientMessageId == null) return;
    final requestId = _requestToClientId.entries
        .firstWhere((e) => e.value == clientMessageId, orElse: () => const MapEntry('', ''))
        .key;
    if (requestId.isEmpty) return;
    _forgetRequest(requestId);
  }

  void _forgetRequest(String requestId) {
    _inflight.remove(requestId);
    _requestToClientId.remove(requestId);
  }

  /// The `client_message_id` a server error belongs to, so a caller can fail *that* message
  /// instead of every one in flight. Null when the error is not attributable to a send.
  String? clientMessageIdForRequest(String requestId) => _requestToClientId[requestId];

  /// Stop trying to deliver a message over the socket — used once it has been delivered
  /// another way (the REST fallback), so a reconnect does not re-send it.
  void cancelPendingSend(String clientMessageId) {
    _clearInflightFor(clientMessageId);
    _outbox.removeWhere((f) => f['client_message_id'] == clientMessageId);
    _syncOutboxCount();
  }

  void _onClosed() {
    final code = _channel?.closeCode;
    _stopHeartbeat();
    // The socket is gone, so anything unacked never arrived — put it back in the outbox for
    // the next auth.ok rather than leaving it to time out as a failure.
    _requeueInflight();
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

  /// Returns `false` when the offline outbox is full — caller should surface failure.
  bool sendMessage({required String conversationId, required String clientMessageId, required String body}) {
    final requestId = uuidV4(_random);
    final frame = sendFrame(requestId: requestId, conversationId: conversationId, clientMessageId: clientMessageId, body: body);
    if (_status.value == RealtimeStatus.ready) {
      // Held until acked: a write to a half-open socket reports success but arrives nowhere,
      // so this is what lets the frame be re-queued rather than lost.
      _inflight[requestId] = frame;
      _requestToClientId[requestId] = clientMessageId;
      _sink(frame);
      return true;
    }
    if (_outbox.length >= maxOutboxSize) return false;
    _outbox.add(frame); // flushed on next auth.ok
    _syncOutboxCount();
    return true;
  }

  void _syncOutboxCount() => _outboxCount.value = _outbox.length;

  void sendTyping(String conversationId, {required bool active}) => _sink(typingFrame(conversationId, active: active));

  void markRead(String conversationId, String throughMessageId) => _sink(readFrame(conversationId, throughMessageId));

  /// Acknowledge receipt up to [throughMessageId], so the sender can show a delivered tick.
  ///
  /// Returns whether the frame was sent. Gated on the *server's* protocol version: a v1 instance
  /// would answer `unsupported_frame`, and during a staged rollout this build routinely meets
  /// one. The caller uses the result to decide whether delivery state is available on this
  /// connection at all, rather than waiting for a tick that is never coming.
  bool markDelivered(String conversationId, String throughMessageId) {
    if (!supportsProtocol(kDeliveryProtocolVersion)) return false;
    _sink(deliveredFrame(conversationId, throughMessageId));
    return true;
  }

  void _sink(Map<String, dynamic> frame) {
    if (_status.value == RealtimeStatus.ready || frame['type'] == 'auth') {
      _channel?.sink.add(jsonEncode(frame));
    }
  }

  /// On logout: drop the socket and forget subscriptions + queued sends.
  void clear() {
    _subscriptions.clear();
    _outbox.clear();
    _inflight.clear();
    _requestToClientId.clear();
    _syncOutboxCount();
    _teardown();
  }

  /// App backgrounded: drop the socket so the server sees us offline (push fires
  /// promptly instead of waiting for a ping-timeout), but KEEP subscriptions, queued
  /// sends, and the "had a connection" flag so [resume] reconnects and REST-syncs.
  /// No auto-reconnect happens until [resume].
  void suspend() {
    if (_disposed) return;
    _teardown(keepConnectionFlag: true);
  }

  /// App foregrounded: reconnect. On `auth.ok` this restores subscriptions and fires
  /// `reconnected` (the cue to REST-sync any messages missed while backgrounded).
  void resume() => connect();

  void _teardown({bool keepConnectionFlag = false}) {
    _cancelReconnect();
    _stopHeartbeat();
    _requeueInflight();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    // Keep _hadConnection on suspend so resume()'s auth.ok counts as a reconnect
    // (→ fires `reconnected` → REST-sync). Reset it on logout/dispose.
    if (!keepConnectionFlag) _hadConnection = false;
    if (!_disposed) _status.value = RealtimeStatus.disconnected;
  }

  /// Move unacked sends back to the outbox so the next `auth.ok` re-sends them. Safe because
  /// the server is idempotent on `client_message_id` — a duplicate is acked, never stored twice.
  void _requeueInflight() {
    if (_inflight.isEmpty) return;
    final pending = List.of(_inflight.values);
    _inflight.clear();
    _requestToClientId.clear();
    final room = maxOutboxSize - _outbox.length;
    if (room <= 0) return; // outbox already full — the caller surfaces failure as before
    _outbox.insertAll(0, pending.take(room)); // oldest first: preserve send order
    _syncOutboxCount();
  }

  void dispose() {
    _disposed = true;
    _teardown();
    _events.close();
    _reconnected.close();
    _status.dispose();
    _outboxCount.dispose();
  }
}

Uri _wsUrl() {
  // http://host/api/v1 → ws://host/api/v1/ws ; https → wss
  final ws = AppConstants.apiBaseUrl.replaceFirst('http', 'ws');
  return Uri.parse('$ws/ws');
}

/// Suspends the socket when the app is backgrounded and resumes it on foreground.
/// Transient states (`inactive`/`hidden` — control centre, app switcher) are ignored so
/// the socket only drops on a real background.
class RealtimeLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onBackground;
  final VoidCallback onForeground;
  RealtimeLifecycleObserver({required this.onBackground, required this.onForeground});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        onBackground();
      case AppLifecycleState.resumed:
        onForeground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}

/// Singleton client tied to auth + app lifecycle: connected only while signed in AND
/// foregrounded. Backgrounding suspends the socket (so "backgrounded" == "offline" →
/// push fires promptly); foregrounding resumes it. Clears on sign-out.
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(
    url: _wsUrl(),
    tokenProvider: () async => Supabase.instance.client.auth.currentSession?.accessToken,
  );

  var foreground = true;
  bool signedIn() => ref.read(authNotifierProvider).asData?.value != null;

  final observer = RealtimeLifecycleObserver(
    onBackground: () {
      foreground = false;
      client.suspend();
    },
    onForeground: () {
      foreground = true;
      if (signedIn()) client.resume();
    },
  );
  WidgetsBinding.instance.addObserver(observer);

  ref.listen<AsyncValue<AuthUser?>>(authNotifierProvider, (_, next) {
    if (next.asData?.value != null) {
      // Defer connecting until foreground so a token refresh while backgrounded
      // can't silently reopen the socket (which would defeat the offline push).
      if (foreground) client.connect();
    } else {
      client.clear();
    }
  }, fireImmediately: true);

  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(observer);
    client.dispose();
  });
  return client;
});

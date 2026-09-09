import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/core/realtime/ws_protocol.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/notifications/providers/notifications_provider.dart';

class _MockAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'user-me',
        email: 'me@livingstone.edu',
        role: 'student',
        profileCompleted: true,
      );
}

class _FakeRealtime extends RealtimeClient {
  final _ev = StreamController<InboundEvent>.broadcast();
  final _rc = StreamController<void>.broadcast();
  _FakeRealtime() : super(url: Uri.parse('ws://test'), tokenProvider: _noToken);
  static Future<String?> _noToken() async => null;

  @override
  Stream<InboundEvent> get events => _ev.stream;
  @override
  Stream<void> get reconnected => _rc.stream;

  void emit(InboundEvent e) => _ev.add(e);
  Future<void> closeStreams() async {
    await _ev.close();
    await _rc.close();
  }
}

class _Adapter implements HttpClientAdapter {
  int unreadCount;
  bool markAllCalled = false;

  _Adapter({this.unreadCount = 0});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (o.path.contains('/notifications/unread-count') && o.method == 'GET') {
      return ResponseBody.fromString(
        '{"count":$unreadCount}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    if (o.path.endsWith('/notifications/read') && o.method == 'POST') {
      markAllCalled = true;
      unreadCount = 0;
      return ResponseBody.fromString('', 204);
    }
    if (o.path.endsWith('/notifications') && o.method == 'GET') {
      return ResponseBody.fromString(
        '[]',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    return ResponseBody.fromString('{"detail":"unexpected ${o.method} ${o.path}"}', 500);
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _stubApi(_Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/'))..httpClientAdapter = adapter;
  return ApiClient(dio: dio);
}

NotificationEvent _notif() => NotificationEvent({
      'id': 'n1',
      'type': 'connection_accepted',
      'read': false,
      'created_at': '2026-09-08T12:00:00.000Z',
    });

Future<(ProviderContainer, _FakeRealtime, _Adapter, ProviderSubscription<int>)> _ready({
  int unread = 0,
}) async {
  final rt = _FakeRealtime();
  final adapter = _Adapter(unreadCount: unread);
  final c = ProviderContainer(overrides: [
    authNotifierProvider.overrideWith(_MockAuth.new),
    realtimeClientProvider.overrideWithValue(rt),
    apiClientProvider.overrideWith((ref) => _stubApi(adapter)),
  ]);
  // Keep actively listened so build + seed run eagerly (same pattern as unread_provider_test).
  final sub = c.listen(notificationCountProvider, (_, _) {}, fireImmediately: true);
  await c.read(authNotifierProvider.future);
  await pumpEventQueue();
  return (c, rt, adapter, sub);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seeds unread count from the server', () async {
    final (c, rt, _, sub) = await _ready(unread: 4);
    expect(c.read(notificationCountProvider), 4);
    sub.close();
    await rt.closeStreams();
    c.dispose();
  });

  test('increments on a live notification event', () async {
    final (c, rt, _, sub) = await _ready(unread: 1);
    rt.emit(_notif());
    await pumpEventQueue();
    expect(c.read(notificationCountProvider), 2);
    sub.close();
    await rt.closeStreams();
    c.dispose();
  });

  test('markAllRead zeros the badge and hits the server', () async {
    final (c, rt, adapter, sub) = await _ready(unread: 3);
    await c.read(notificationCountProvider.notifier).markAllRead();
    expect(c.read(notificationCountProvider), 0);
    expect(adapter.markAllCalled, isTrue);
    sub.close();
    await rt.closeStreams();
    c.dispose();
  });

  test('keepAlive: WS +1 still applies after the last listener is closed', () async {
    // Without keepAlive, closing the last listener would dispose the notifier (cancel the
    // events subscription). A ping in that window would be lost; the next read would re-seed
    // from the API and stay at the old count.
    final (c, rt, _, sub) = await _ready(unread: 2);
    expect(c.read(notificationCountProvider), 2);

    sub.close(); // last listener gone — provider must stay alive via keepAlive

    rt.emit(_notif());
    await pumpEventQueue();

    expect(c.read(notificationCountProvider), 3);
    await rt.closeStreams();
    c.dispose();
  });
}

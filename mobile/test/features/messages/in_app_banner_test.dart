import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/core/notifications/in_app_banner.dart';
import 'package:lc_connect/core/notifications/notification_sound.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/core/realtime/ws_protocol.dart';
import 'package:lc_connect/core/storage/secure_storage.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/messages/providers/in_app_message_listener.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';
import 'package:lc_connect/features/messages/providers/unread_provider.dart';

const _me = 'me';

class _MockAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async =>
      AuthUser(id: _me, email: 'me@x.com', role: 'student', profileCompleted: true);
}

/// No-op sound so tests never touch the audio plugin.
class _SilentSound extends NotificationSound {
  @override
  Future<void> play() async {}
}

class _MockThreads extends ThreadsNotifier {
  final List<MessageThread> _fixed;
  _MockThreads(this._fixed);
  @override
  Future<List<MessageThread>> build() async => _fixed;
}

class _FakeRealtime extends RealtimeClient {
  final _ev = StreamController<InboundEvent>.broadcast();
  _FakeRealtime() : super(url: Uri.parse('ws://test'), tokenProvider: _noToken);
  static Future<String?> _noToken() async => null;
  @override
  Stream<InboundEvent> get events => _ev.stream;
  @override
  Stream<void> get reconnected => const Stream.empty();
  void emit(InboundEvent e) => _ev.add(e);
  Future<void> closeStreams() => _ev.close();
}

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString('{"total":0,"per_conversation":{}}', 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
  @override
  void close({bool force = false}) {}
}

ApiClient _stubApi() {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/'))..httpClientAdapter = _StubAdapter();
  return ApiClient(SecureStorage(), dio: dio);
}

final _partner = MessagePartner(
  profileId: 'p1',
  userId: 'partner',
  displayName: 'Maya Chen',
  interests: const [],
  lookingFor: const [],
  languagesSpoken: const [],
  languagesLearning: const [],
);

final _thread = MessageThread(matchId: 'conv-1', partner: _partner);

ConversationUpdated _incoming(String conv, String sender, {String body = 'hey there'}) =>
    ConversationUpdated(conv, {
      'id': 'm-$sender',
      'match_id': conv,
      'sender_id': sender,
      'body': body,
      'created_at': '2026-01-01T00:00:00.000Z',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── CurrentBannerNotifier ─────────────────────────────────────────
  group('CurrentBannerNotifier', () {
    test('show sets the banner; dismiss clears it', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(currentBannerProvider.notifier);

      n.show(const BannerData(conversationId: 'x', title: 'A', body: 'hi'));
      expect(c.read(currentBannerProvider)?.title, 'A');

      n.dismiss();
      expect(c.read(currentBannerProvider), isNull);
    });

    test('a newer message replaces the current banner (never stacks)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(currentBannerProvider.notifier);

      n.show(const BannerData(conversationId: 'x', title: 'A', body: 'first'));
      n.show(const BannerData(conversationId: 'y', title: 'B', body: 'second'));
      expect(c.read(currentBannerProvider)?.body, 'second');
      expect(c.read(currentBannerProvider)?.conversationId, 'y');
    });
  });

  // ── Listener filters ──────────────────────────────────────────────
  Future<(ProviderContainer, _FakeRealtime)> boot() async {
    final rt = _FakeRealtime();
    final c = ProviderContainer(overrides: [
      authNotifierProvider.overrideWith(_MockAuth.new),
      realtimeClientProvider.overrideWithValue(rt),
      apiClientProvider.overrideWith((ref) => _stubApi()),
      threadsNotifierProvider.overrideWith(() => _MockThreads([_thread])),
      notificationSoundProvider.overrideWithValue(_SilentSound()),
    ]);
    c.listen(inAppMessageListenerProvider, (_, _) {}, fireImmediately: true);
    await c.read(authNotifierProvider.future);
    await c.read(threadsNotifierProvider.future); // resolve so the sender name is available
    await pumpEventQueue();
    return (c, rt);
  }

  test('shows a banner for a partner message with the sender name', () async {
    final (c, rt) = await boot();
    rt.emit(_incoming('conv-1', 'partner', body: 'study tonight?'));
    await pumpEventQueue();

    final banner = c.read(currentBannerProvider);
    expect(banner, isNotNull);
    expect(banner!.title, 'Maya Chen');
    expect(banner.body, 'study tonight?');
    expect(banner.conversationId, 'conv-1');
    await rt.closeStreams();
    c.dispose();
  });

  test('suppresses my own message', () async {
    final (c, rt) = await boot();
    rt.emit(_incoming('conv-1', _me));
    await pumpEventQueue();
    expect(c.read(currentBannerProvider), isNull);
    await rt.closeStreams();
    c.dispose();
  });

  test('suppresses a message for the conversation currently open', () async {
    final (c, rt) = await boot();
    c.read(unreadProvider.notifier).enterConversation('conv-1');
    rt.emit(_incoming('conv-1', 'partner'));
    await pumpEventQueue();
    expect(c.read(currentBannerProvider), isNull);
    await rt.closeStreams();
    c.dispose();
  });

  // ── InAppBannerHost widget ────────────────────────────────────────
  testWidgets('host renders the banner title + body when set', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Stack(children: [InAppBannerHost()]),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing); // nothing shown yet

    c.read(currentBannerProvider.notifier).show(
          const BannerData(conversationId: 'conv-1', title: 'Maya Chen', body: 'hi there'),
        );
    await tester.pump(); // build
    await tester.pump(const Duration(milliseconds: 300)); // slide-in

    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('hi there'), findsOneWidget);

    // Cancel the 4s auto-dismiss timer so none is left pending at teardown.
    c.read(currentBannerProvider.notifier).dismiss();
    await tester.pumpAndSettle();
  });
}

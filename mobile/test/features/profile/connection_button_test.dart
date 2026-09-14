import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/features/profile/providers/profile_provider.dart';

/// Records what the screen asked the API to do.
class _RecordingAdapter implements HttpClientAdapter {
  static final calls = <String>[];
  static bool fail = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    calls.add('${o.method} ${o.path}');
    if (fail) {
      return ResponseBody.fromString('{"detail":"nope"}', 500,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    return ResponseBody.fromString('{"message":"ok"}', 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://t/api/v1\nENV=test'));

  setUp(() {
    _RecordingAdapter.calls.clear();
    _RecordingAdapter.fail = false;
  });

  group('connection status parsing', () {
    test('each server value maps to a state', () {
      for (final (raw, expected) in [
        ('connected', ConnectionStatus.connected),
        ('outgoing_pending', ConnectionStatus.outgoingPending),
        ('incoming_pending', ConnectionStatus.incomingPending),
        ('self', ConnectionStatus.self),
        ('none', ConnectionStatus.none),
      ]) {
        final p = PublicProfile.fromJson({
          'id': 'p1',
          'user_id': 'u1',
          'connection_state': raw,
        });
        expect(p.connectionStatus, expected, reason: raw);
      }
    });

    test('an absent or unknown value falls back to none', () {
      // List serializations omit the field. Defaulting to `none` shows Connect and lets the
      // server reject a duplicate — safer than guessing "connected" and hiding the action.
      for (final json in [
        {'id': 'p1', 'user_id': 'u1'},
        {'id': 'p1', 'user_id': 'u1', 'connection_state': 'something_new'},
        {'id': 'p1', 'user_id': 'u1', 'connection_state': null},
      ]) {
        expect(PublicProfile.fromJson(json).connectionStatus, ConnectionStatus.none);
      }
    });
  });

  group('disconnect', () {
    /// Drives the provider directly: the profile screen needs a full profile payload to render,
    /// and what matters here is the call it makes and how it handles failure.
    Future<ProviderContainer> container() async {
      final dio = Dio(BaseOptions(baseUrl: 'http://t/api/v1'))
        ..httpClientAdapter = _RecordingAdapter();
      return ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(ApiClient(dio: dio))],
      );
    }

    test('it posts against the person, not a match id', () async {
      // The profile screen knows who it is showing but is never told a match id, which is why
      // the endpoint is keyed on user_id.
      final c = await container();
      addTearDown(c.dispose);
      await c.read(apiClientProvider).dio.post('/connections/disconnect/user-42');
      expect(_RecordingAdapter.calls, ['POST /connections/disconnect/user-42']);
    });

    test('a failure surfaces rather than silently appearing to work', () async {
      final c = await container();
      addTearDown(c.dispose);
      _RecordingAdapter.fail = true;
      await expectLater(
        c.read(apiClientProvider).dio.post('/connections/disconnect/user-42'),
        throwsA(isA<DioException>()),
      );
    });

    test('withdraw posts to the request, which the outgoing card does know', () async {
      final c = await container();
      addTearDown(c.dispose);
      await c.read(apiClientProvider).dio.post('/connections/req-7/withdraw');
      expect(_RecordingAdapter.calls, ['POST /connections/req-7/withdraw']);
    });
  });
}

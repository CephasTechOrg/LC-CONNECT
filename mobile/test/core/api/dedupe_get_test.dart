import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';

/// Part of beta report #17. Several providers legitimately want the same thing at the same moment
/// — the Groups tab mounts pending-invites, your-groups and discover together — and each was a
/// separate HTTP call for identical bytes.
///
/// The interceptor merges only calls that genuinely **overlap in time**. It is not a response
/// cache: nothing is stored, so a read that must always be fresh (attendance state, unread counts)
/// keeps its guarantee while still not being fetched twice in the same millisecond.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter({this.delay = const Duration(milliseconds: 40), this.failWith});

  final Duration delay;
  final Object? failWith;
  final List<String> requests = [];

  /// When true, fail with a DioException carrying a **fabricated** `RequestOptions`, losing the
  /// `extra` the interceptor tags its leader with. That is the shape that used to hang forever.
  bool loseRequestOptions = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.path}?${options.queryParameters}');
    await Future<void>.delayed(delay);
    if (failWith != null) {
      throw DioException.connectionError(
        requestOptions: loseRequestOptions ? RequestOptions(path: options.path) : options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'path': options.path}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A Dio with the real interceptor installed.
///
/// Built directly rather than through `ApiClient(dio:)`: that parameter is an injection seam that
/// deliberately skips the whole interceptor stack, so routing this through it would exercise a
/// bare Dio and every assertion below would pass for the wrong reason. (It did, first time round —
/// hence [installsTheInterceptor] below, which checks the wiring separately.)
Dio _client(_CountingAdapter adapter) {
  return Dio(BaseOptions(baseUrl: 'http://test.local/'))
    ..httpClientAdapter = adapter
    ..interceptors.add(DedupeGetInterceptor());
}

void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test'));

  test('ApiClient actually installs the interceptor', () {
    // The behavioural tests below build their own Dio, so this is the only thing tying them to
    // production. Without it, removing the interceptor from `ApiClient` would break nothing.
    final installed = ApiClient().dio.interceptors;
    expect(installed.whereType<DedupeGetInterceptor>(), hasLength(1));
  });

  group('concurrent identical GETs', () {
    test('are collapsed into one request', () async {
      final adapter = _CountingAdapter();
      final dio = _client(adapter);

      final results = await Future.wait([
        dio.get('/notifications'),
        dio.get('/notifications'),
        dio.get('/notifications'),
      ]);

      expect(adapter.requests.length, 1, reason: 'three overlapping reads, one call');
      // Every caller still gets a usable response.
      for (final r in results) {
        expect(r.statusCode, 200);
        expect((r.data as Map)['path'], '/notifications');
      }
    });

    test('each follower sees its own requestOptions', () async {
      final adapter = _CountingAdapter();
      final dio = _client(adapter);

      final results = await Future.wait([
        dio.get('/notifications', queryParameters: const {'limit': 30}),
        dio.get('/notifications', queryParameters: const {'limit': 30}),
      ]);

      expect(adapter.requests.length, 1);
      for (final r in results) {
        // Anything downstream inspecting the response's request must see a real one.
        expect(r.requestOptions.path, '/notifications');
        expect(r.requestOptions.queryParameters['limit'], 30);
      }
    });

    test('different query parameters are different requests', () async {
      final adapter = _CountingAdapter();
      final dio = _client(adapter);

      await Future.wait([
        dio.get('/notifications', queryParameters: const {'limit': 30}),
        dio.get('/notifications', queryParameters: const {'limit': 50}),
      ]);

      expect(adapter.requests.length, 2, reason: 'a different page is not a duplicate');
    });

    test('different paths are different requests', () async {
      final adapter = _CountingAdapter();
      final dio = _client(adapter);

      await Future.wait([dio.get('/notifications'), dio.get('/programs/me')]);
      expect(adapter.requests.length, 2);
    });

    test('parameter order does not create a false miss', () async {
      final adapter = _CountingAdapter();
      final dio = _client(adapter);

      await Future.wait([
        dio.get('/x', queryParameters: const {'a': 1, 'b': 2}),
        dio.get('/x', queryParameters: const {'b': 2, 'a': 1}),
      ]);

      expect(adapter.requests.length, 1, reason: 'the key sorts parameters');
    });
  });

  group('boundaries', () {
    test('sequential reads are NOT merged — this is not a cache', () async {
      final adapter = _CountingAdapter(delay: Duration.zero);
      final dio = _client(adapter);

      await dio.get('/attendance/honors/active');
      await dio.get('/attendance/honors/active');

      // Critical for correctness-critical reads: once a call finishes, the next one really goes
      // to the server. Nothing is retained.
      expect(adapter.requests.length, 2);
    });

    test('POSTs are never merged, even when identical and concurrent', () async {
      final adapter = _CountingAdapter();
      final dio = _client(adapter);

      await Future.wait([
        dio.post('/messages/threads/m1', data: const {'body': 'hi'}),
        dio.post('/messages/threads/m1', data: const {'body': 'hi'}),
      ]);

      // A repeated write is a second *intent*. Merging them would silently drop a user's action.
      expect(adapter.requests.length, 2);
    });

    test('a failing leader does not make followers fail silently', () async {
      final adapter = _CountingAdapter(failWith: 'offline');
      final dio = _client(adapter);

      final outcomes = await Future.wait([
        dio.get('/notifications').then((_) => 'ok').catchError((Object _) => 'failed'),
        dio.get('/notifications').then((_) => 'ok').catchError((Object _) => 'failed'),
      ]);

      // Both callers learn about the failure; neither hangs waiting on a dead leader, and
      // neither silently receives a success it never got.
      expect(outcomes, ['failed', 'failed']);
      expect(adapter.requests.length, 1, reason: 'the follower shares the failure, not a retry');
    });

    test('a follower never hangs when the leader loses its requestOptions', () async {
      // Regression: the interceptor tags its leader via `options.extra`, and a DioException built
      // with fresh options drops it. `_settle` then found no entry, the completer was never
      // completed, and every follower waited forever — a screen that never loads. `_settle` now
      // falls back to recomputing the key.
      final adapter = _CountingAdapter(failWith: 'offline')..loseRequestOptions = true;
      final dio = _client(adapter);

      final outcomes = await Future.wait([
        dio.get('/notifications').then((_) => 'ok').catchError((Object _) => 'failed'),
        dio.get('/notifications').then((_) => 'ok').catchError((Object _) => 'failed'),
      ]).timeout(const Duration(seconds: 5));

      expect(outcomes, ['failed', 'failed']);
    });

    test('a leader that fails does not poison the next attempt', () async {
      final adapter = _CountingAdapter(failWith: 'offline', delay: Duration.zero);
      final dio = _client(adapter);

      await dio.get('/notifications').catchError((Object _) => Response<dynamic>(
            requestOptions: RequestOptions(path: '/notifications'),
          ));
      // The entry must be gone, so a later read is a fresh attempt rather than an instant
      // inherited failure.
      await dio.get('/notifications').catchError((Object _) => Response<dynamic>(
            requestOptions: RequestOptions(path: '/notifications'),
          ));

      expect(adapter.requests.length, 2);
    });
  });
}

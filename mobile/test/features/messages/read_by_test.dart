import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/features/messages/providers/read_by_provider.dart';

/// Report #21's group answer. A group bubble carries no delivered or read tick — that needs a
/// rule for which members count and every member's boundary held on the client — so "read by" is
/// the affordance instead.
class _ReadByAdapter implements HttpClientAdapter {
  _ReadByAdapter({this.rows = const [], this.status = 200});

  final List<Map<String, dynamic>> rows;
  final int status;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    paths.add(o.path);
    return ResponseBody.fromString(
      jsonEncode(status == 200 ? rows : {'detail': 'nope'}),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _row(String id, {String? name, String? avatar}) => {
      'user_id': id,
      'display_name': name,
      'avatar_url': avatar,
    };

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test');
  });

  ProviderContainer containerFor(_ReadByAdapter adapter) {
    final container = ProviderContainer(
        // Riverpod 3 retries a failed provider on a backoff. Left on, the error assertion below
        // waits on a retry instead of observing the failure.
        retry: (_, _) => null,
        overrides: [
      apiClientProvider.overrideWith((ref) => ApiClient(
          dio: Dio(BaseOptions(baseUrl: 'http://test.local/'))..httpClientAdapter = adapter)),
        ]);
    addTearDown(container.dispose);
    return container;
  }

  group('MessageReader', () {
    test('reads the name and avatar', () {
      final reader = MessageReader.fromJson(_row('u1', name: 'Maya Chen', avatar: 'a.jpg'));
      expect(reader.userId, 'u1');
      expect(reader.name, 'Maya Chen');
      expect(reader.avatarUrl, 'a.jpg');
    });

    test('a member with no profile row still has a usable name', () {
      // A missing profile must not drop the row: the list would then disagree with itself about
      // how many people have read the message.
      expect(MessageReader.fromJson(_row('u1')).name, 'Member');
    });

    test('a blank display name falls back rather than rendering emptiness', () {
      expect(MessageReader.fromJson(_row('u1', name: '   ')).name, 'Member');
    });
  });

  group('messageReadByProvider', () {
    test('requests the message it was asked about', () async {
      final adapter = _ReadByAdapter(rows: [_row('u1', name: 'Maya')]);
      final container = containerFor(adapter);

      await container.read(messageReadByProvider('msg-7').future);

      expect(adapter.paths.single, '/messages/msg-7/read-by');
    });

    test('parses the readers', () async {
      final adapter = _ReadByAdapter(rows: [
        _row('u1', name: 'Maya'),
        _row('u2', name: 'Ethan'),
      ]);
      final container = containerFor(adapter);

      final readers = await container.read(messageReadByProvider('msg-7').future);

      expect(readers.map((r) => r.name), ['Maya', 'Ethan']);
    });

    test('an empty list is a valid answer, not an error', () async {
      // Nobody has caught up yet — the normal state for a message just sent.
      final container = containerFor(_ReadByAdapter());
      expect(await container.read(messageReadByProvider('msg-7').future), isEmpty);
    });

    test('each message is cached separately', () async {
      final adapter = _ReadByAdapter(rows: [_row('u1', name: 'Maya')]);
      final container = containerFor(adapter);

      await container.read(messageReadByProvider('msg-1').future);
      await container.read(messageReadByProvider('msg-2').future);

      expect(adapter.paths, ['/messages/msg-1/read-by', '/messages/msg-2/read-by']);
    });

    test('reopening the sheet inside the window does not refetch', () async {
      final adapter = _ReadByAdapter(rows: [_row('u1', name: 'Maya')]);
      final container = containerFor(adapter);

      final sub = container.listen(messageReadByProvider('msg-7'), (_, _) {});
      await container.read(messageReadByProvider('msg-7').future);
      sub.close();
      await container.read(messageReadByProvider('msg-7').future);

      expect(adapter.paths, hasLength(1));
    });

    test('a failure surfaces as an error rather than an empty list', () async {
      // The distinction is the whole point: rendering a failed request as "no one has read this"
      // would state something false about other people.
      final container = containerFor(_ReadByAdapter(status: 500));

      // Observed through a subscription rather than awaited: awaiting the future of a provider
      // that throws leaves the expectation hanging on the pending error instead of reading it.
      final sub = container.listen(messageReadByProvider('msg-7'), (_, _) {});
      addTearDown(sub.close);
      // A few event-loop turns: the request itself is async, so one microtask only gets as far
      // as `loading`.
      for (var i = 0; i < 5 && !sub.read().hasError; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(sub.read().hasError, isTrue);
      expect(sub.read().value, isNull, reason: 'never an empty list on failure');
    });
  });
}

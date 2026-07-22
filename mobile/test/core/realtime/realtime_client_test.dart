import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';

void main() {
  group('backoffDelay', () {
    test('stays within [0, min(cap, base * 2^attempt)]', () {
      final rng = Random(42);
      for (var attempt = 0; attempt < 12; attempt++) {
        final ceiling = (500 * (1 << attempt)).clamp(0, 30000);
        for (var i = 0; i < 50; i++) {
          final d = backoffDelay(attempt, rng).inMilliseconds;
          expect(d, inInclusiveRange(0, ceiling));
        }
      }
    });

    test('is capped at 30s for large attempts', () {
      final rng = Random(1);
      for (var i = 0; i < 100; i++) {
        expect(backoffDelay(40, rng).inMilliseconds, inInclusiveRange(0, 30000));
      }
    });
  });

  group('uuidV4', () {
    test('has v4 shape', () {
      final id = uuidV4(Random(7));
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('is unique across calls', () {
      final ids = List.generate(1000, (_) => uuidV4());
      expect(ids.toSet().length, 1000);
    });
  });
}

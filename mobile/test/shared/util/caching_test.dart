import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/shared/util/caching.dart';

/// Beta report #17 — "excessive loading/refetching".
///
/// Two separate causes, and both needed fixing:
///
///  * `autoDispose` threw a provider's value away the moment its screen unmounted, so every visit
///    was a cold fetch. With `ShellRoute` replacing the stack on each tab change, opening the
///    Groups tab cost three requests and three skeletons *every time*. [cacheFor] holds the value
///    for a window instead.
///  * `AsyncValue.when` shows `loading` during **any** reload, so even a cached screen collapsed
///    to a skeleton the instant it revalidated — the data was right there. [AsyncValueCache.cached]
///    prefers a known value, however stale.
void main() {
  group('cacheFor', () {
    test('a provider is not refetched when re-read inside the window', () {
      fakeAsync((async) {
        var fetches = 0;
        final provider = FutureProvider.autoDispose<int>((ref) {
          cacheFor(ref, const Duration(minutes: 5));
          fetches++;
          return Future.value(fetches);
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Visit the screen.
        container.listen(provider, (_, _) {}).close();
        async.elapse(const Duration(seconds: 1));
        expect(fetches, 1);

        // Leave and come straight back — the autoDispose case that used to refetch.
        container.listen(provider, (_, _) {}).close();
        async.elapse(const Duration(seconds: 1));
        expect(fetches, 1, reason: 'a revisit inside the window must reuse the cached value');
      });
    });

    test('the value is released once the window elapses', () {
      fakeAsync((async) {
        var fetches = 0;
        final provider = FutureProvider.autoDispose<int>((ref) {
          cacheFor(ref, const Duration(minutes: 5));
          fetches++;
          return Future.value(fetches);
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.listen(provider, (_, _) {}).close();
        async.elapse(const Duration(seconds: 1));
        expect(fetches, 1);

        // Past the window: the cache must expire rather than pin the value for the app's life,
        // which is what a bare `keepAlive()` would do.
        async.elapse(const Duration(minutes: 6));
        container.listen(provider, (_, _) {}).close();
        async.elapse(const Duration(seconds: 1));
        expect(fetches, 2);
      });
    });

    test('a listener held past the window keeps the provider alive', () {
      fakeAsync((async) {
        var fetches = 0;
        final provider = FutureProvider.autoDispose<int>((ref) {
          cacheFor(ref, const Duration(minutes: 5));
          fetches++;
          return Future.value(fetches);
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final sub = container.listen(provider, (_, _) {});
        async.elapse(const Duration(minutes: 10));
        expect(fetches, 1, reason: 'the window must not evict something still being watched');
        sub.close();
      });
    });

    test('an explicit invalidate still refetches — caching must not defeat a mutation', () {
      fakeAsync((async) {
        var fetches = 0;
        final provider = FutureProvider.autoDispose<int>((ref) {
          cacheFor(ref, const Duration(minutes: 5));
          fetches++;
          return Future.value(fetches);
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final sub = container.listen(provider, (_, _) {});
        async.elapse(const Duration(seconds: 1));
        expect(fetches, 1);

        // This is how the app keeps cached lists correct after a join/create/accept.
        container.invalidate(provider);
        async.elapse(const Duration(seconds: 1));
        expect(fetches, 2);
        sub.close();
      });
    });

    test('each family argument caches separately', () {
      fakeAsync((async) {
        final calls = <String>[];
        final provider = FutureProvider.autoDispose.family<String, String>((ref, key) {
          cacheFor(ref, const Duration(minutes: 5));
          calls.add(key);
          return Future.value(key);
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.listen(provider('a'), (_, _) {}).close();
        container.listen(provider('b'), (_, _) {}).close();
        async.elapse(const Duration(seconds: 1));
        expect(calls, ['a', 'b']);

        // Backspacing a search term back to one already typed should not re-query.
        container.listen(provider('a'), (_, _) {}).close();
        async.elapse(const Duration(seconds: 1));
        expect(calls, ['a', 'b'], reason: "'a' was still cached");
      });
    });

    test('the timer does not outlive a provider disposed for another reason', () {
      fakeAsync((async) {
        final provider = FutureProvider.autoDispose<int>((ref) {
          cacheFor(ref, const Duration(minutes: 5));
          return Future.value(1);
        });
        final container = ProviderContainer();

        container.listen(provider, (_, _) {}).close();
        async.elapse(const Duration(seconds: 1));
        container.dispose();

        // Without the `ref.onDispose(timer.cancel)` in `cacheFor`, the pending timer would fire
        // against a closed link here.
        expect(() => async.elapse(const Duration(minutes: 10)), returnsNormally);
      });
    });
  });

  group('AsyncValue.cached', () {
    String render(AsyncValue<int> value) => value.cached(
          data: (v) => 'data:$v',
          loading: () => 'loading',
          error: (e, _) => 'error',
        );

    test('a first load shows loading', () {
      expect(render(const AsyncValue<int>.loading()), 'loading');
    });

    test('data shows data', () {
      expect(render(const AsyncValue.data(7)), 'data:7');
    });

    test('a first-load failure shows the error', () {
      expect(render(AsyncValue<int>.error(Exception('x'), StackTrace.empty)), 'error');
    });

    test('a refresh over existing data keeps showing the data', () async {
      // The whole point: `when` would say "loading" here and blank the screen.
      var calls = 0;
      final source = FutureProvider<int>((ref) async {
        calls++;
        if (calls > 1) await Future<void>.delayed(const Duration(milliseconds: 50));
        return 7;
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(source, (_, _) {});
      addTearDown(sub.close);

      await container.read(source.future);
      expect(render(sub.read()), 'data:7');

      container.invalidate(source);
      expect(render(sub.read()), 'data:7', reason: 'stale data beats a skeleton');
      expect(sub.read().isRevalidating, isTrue);
    });

    test('a failed refresh keeps showing the last good data', () async {
      var calls = 0;
      final source = FutureProvider<int>((ref) async {
        calls++;
        if (calls > 1) throw Exception('flaky');
        return 7;
      });
      final container = ProviderContainer(retry: (_, _) => null);
      addTearDown(container.dispose);
      final sub = container.listen(source, (_, _) {});
      addTearDown(sub.close);

      await container.read(source.future);
      container.invalidate(source);
      await Future<void>.delayed(Duration.zero);

      // A transient failure must not wipe content the user is reading.
      expect(render(sub.read()), 'data:7');
      expect(sub.read().hasError, isTrue);
    });

    test('isRevalidating is false when there is nothing to revalidate', () {
      expect(const AsyncValue<int>.loading().isRevalidating, isFalse);
      expect(const AsyncValue.data(1).isRevalidating, isFalse);
    });
  });
}

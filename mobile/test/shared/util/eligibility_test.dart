import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/shared/util/eligibility.dart';

/// The rule these tests exist to lock down: **a failure must never read as a denial.**
///
/// Four gated surfaces (Blueprint Bond card, attendance check-in card, attendance scanner, scholar
/// opportunities filter) all hid themselves silently because their providers turned any error into
/// `false`. `Eligibility` separates "no" from "couldn't find out"; these tests pin that separation
/// so a future refactor cannot quietly collapse it again.
void main() {
  group('eligibilityFrom', () {
    test('data that satisfies the test is yes', () {
      expect(eligibilityFrom(const AsyncValue.data(5), (v) => v > 3), Eligibility.yes);
    });

    test('data that fails the test is a confirmed no', () {
      expect(eligibilityFrom(const AsyncValue.data(1), (v) => v > 3), Eligibility.no);
    });

    test('an error is unknown — never no', () {
      final e = eligibilityFrom(
        AsyncValue<int>.error(Exception('offline'), StackTrace.empty),
        (v) => v > 3,
      );
      expect(e, Eligibility.unknown);
      expect(e, isNot(Eligibility.no), reason: 'this conflation was the original bug');
      expect(e.needsRetry, isTrue);
    });

    test('a first load still in flight is pending, not no', () {
      final e = eligibilityFrom(const AsyncValue<int>.loading(), (v) => v > 3);
      expect(e, Eligibility.pending);
      expect(e.isPermitted, isFalse, reason: 'must not render the surface yet');
      expect(e.needsRetry, isFalse, reason: 'loading is not a failure worth reporting');
    });

    // The next two exercise the no-flicker property through a real container refresh rather than
    // by hand-constructing an "AsyncLoading carrying a previous value". Building that state
    // directly needs `copyWithPrevious`, which is Riverpod-internal; driving an actual refresh
    // tests the behaviour clients really see.
    test('a known-but-stale value wins over an in-flight refresh, so surfaces do not blink', () async {
      var loads = 0;
      final source = FutureProvider<int>((ref) async {
        loads++;
        if (loads > 1) await Future<void>.delayed(const Duration(milliseconds: 50));
        return 5;
      });
      final derived = Provider<Eligibility>(
        (ref) => eligibilityFrom(ref.watch(source), (v) => v > 3),
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(derived, (_, _) {});
      addTearDown(sub.close);

      await c.read(source.future);
      expect(sub.read(), Eligibility.yes);

      c.invalidate(source); // refresh now in flight, previous value retained
      expect(
        sub.read(),
        Eligibility.yes,
        reason: 'a surface must not blink to pending while revalidating',
      );
    });

    test('a known-but-stale value also wins over a failed refresh', () async {
      var loads = 0;
      final source = FutureProvider<int>((ref) async {
        loads++;
        if (loads > 1) throw Exception('flaky');
        return 5;
      });
      final derived = Provider<Eligibility>(
        (ref) => eligibilityFrom(ref.watch(source), (v) => v > 3),
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(derived, (_, _) {});
      addTearDown(sub.close);

      await c.read(source.future);
      expect(sub.read(), Eligibility.yes);

      c.invalidate(source);
      await Future<void>.delayed(Duration.zero);
      // Still answerable from what we already know — no reason to nag the user with a retry.
      expect(sub.read(), Eligibility.yes);
      expect(sub.read().needsRetry, isFalse);
    });
  });

  group('eligibilityAll', () {
    test('every gate permitting is yes', () {
      expect(eligibilityAll([Eligibility.yes, Eligibility.yes]), Eligibility.yes);
    });

    test('a confirmed no outranks everything, including unknown', () {
      // Deliberately unlike `&&`: if the user definitively is not a scholar, whether the feature
      // flag could be read is irrelevant. Hiding cleanly beats offering a retry that cannot help.
      expect(eligibilityAll([Eligibility.no, Eligibility.unknown]), Eligibility.no);
      expect(eligibilityAll([Eligibility.unknown, Eligibility.no]), Eligibility.no);
      expect(eligibilityAll([Eligibility.no, Eligibility.pending]), Eligibility.no);
      expect(eligibilityAll([Eligibility.no, Eligibility.yes]), Eligibility.no);
    });

    test('unknown outranks pending', () {
      expect(eligibilityAll([Eligibility.unknown, Eligibility.pending]), Eligibility.unknown);
      expect(eligibilityAll([Eligibility.pending, Eligibility.unknown]), Eligibility.unknown);
    });

    test('pending propagates when nothing has failed', () {
      expect(eligibilityAll([Eligibility.yes, Eligibility.pending]), Eligibility.pending);
    });

    test('an empty gate list permits — vacuous truth, matching `every`', () {
      expect(eligibilityAll(const []), Eligibility.yes);
    });
  });

  group('state predicates', () {
    test('only yes permits rendering', () {
      expect(Eligibility.yes.isPermitted, isTrue);
      for (final e in [Eligibility.no, Eligibility.pending, Eligibility.unknown]) {
        expect(e.isPermitted, isFalse, reason: '$e must not render');
      }
    });

    test('only unknown earns a retry', () {
      expect(Eligibility.unknown.needsRetry, isTrue);
      for (final e in [Eligibility.yes, Eligibility.no, Eligibility.pending]) {
        expect(e.needsRetry, isFalse, reason: '$e must not offer a retry');
      }
    });

    test('no and pending both render nothing, but only one is terminal', () {
      expect(Eligibility.no.isHidden, isTrue);
      expect(Eligibility.pending.isHidden, isTrue);
      expect(Eligibility.unknown.isHidden, isFalse, reason: 'it owes the user a retry instead');
    });
  });
}

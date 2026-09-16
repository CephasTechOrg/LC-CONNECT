import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the signed-in user may see a gated surface.
///
/// This type exists because a `bool` cannot express the difference between **"no"** and
/// **"we could not find out"** — and collapsing the two is what made the Blueprint Bond card, the
/// attendance check-in card, the attendance scanner, and the scholar opportunities filter vanish
/// silently. The providers behind them turned any failure (`catch (_) { return false; }`, or an
/// `AsyncError` falling back to an empty list) into a confident "not eligible", the widget rendered
/// `SizedBox.shrink()`, and nothing ever retried — so one failed request at launch hid four
/// surfaces for the rest of the session.
///
/// Four states, because the right UI differs for each:
///
/// | State | Meaning | What a surface should do |
/// |---|---|---|
/// | [yes] | confirmed permitted | render |
/// | [no] | confirmed **not** permitted | render nothing |
/// | [pending] | still resolving | render nothing — **do not** offer a retry yet |
/// | [unknown] | could not determine | render a retry; never claim ineligibility |
///
/// [pending] and [unknown] are deliberately separate. Showing a retry while the first request is
/// still in flight is noise, and hiding forever after it fails is the original bug.
enum Eligibility {
  yes,
  no,
  pending,
  unknown;

  /// True only for a confirmed permit. Use for `if (…) render`.
  bool get isPermitted => this == Eligibility.yes;

  /// Whether the user is owed a retry affordance.
  ///
  /// Distinct from `!isPermitted`: a confirmed [no] and a still-loading [pending] are both
  /// "don't render", but neither is a failure to report.
  bool get needsRetry => this == Eligibility.unknown;

  /// Whether a surface should render nothing at all right now.
  bool get isHidden => this == Eligibility.no || this == Eligibility.pending;
}

/// Derive an [Eligibility] from an [AsyncValue] source without losing the failure case.
///
/// Precedence is deliberate:
///
/// 1. **Any known value wins — even a stale one mid-refresh.** `AsyncValue.value` survives a
///    refresh, so a surface does not blink off and back on when the source revalidates. This
///    preserves the no-flicker behaviour the previous `memberships.asData?.value ?? …` fallback was
///    written for, without also swallowing errors.
/// 2. **Otherwise an error means [Eligibility.unknown]**, never [Eligibility.no].
/// 3. **Otherwise [Eligibility.pending]** — the first load has not answered yet.
Eligibility eligibilityFrom<T>(AsyncValue<T> source, bool Function(T value) test) {
  final known = source.value;
  if (known != null) return test(known) ? Eligibility.yes : Eligibility.no;
  if (source.hasError) return Eligibility.unknown;
  return Eligibility.pending;
}

/// Combine two independent gates that must **both** permit a surface.
///
/// Order matters, and it is the opposite of a plain `&&`:
///
/// - A confirmed [Eligibility.no] wins outright. If the user is definitively not a scholar, it is
///   irrelevant whether the feature flag could be read — the answer is a settled "no", so the
///   surface hides cleanly rather than offering a pointless retry.
/// - Otherwise [Eligibility.unknown] wins over [Eligibility.pending], because an unresolved failure
///   is the more actionable state to surface.
Eligibility eligibilityAll(Iterable<Eligibility> gates) {
  var sawUnknown = false;
  var sawPending = false;
  for (final gate in gates) {
    switch (gate) {
      case Eligibility.no:
        return Eligibility.no;
      case Eligibility.unknown:
        sawUnknown = true;
      case Eligibility.pending:
        sawPending = true;
      case Eligibility.yes:
        break;
    }
  }
  if (sawUnknown) return Eligibility.unknown;
  if (sawPending) return Eligibility.pending;
  return Eligibility.yes;
}

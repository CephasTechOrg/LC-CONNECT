import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/realtime/realtime_client.dart';

/// Re-runs [onStale] at the two moments cached state is most likely to be wrong: when the app
/// returns to the foreground, and when the realtime socket reconnects.
///
/// Call it from inside a provider body, before the first `await`.
///
/// ```dart
/// final myProvider = FutureProvider<Thing>((ref) async {
///   keepFresh(ref, onStale: ref.invalidateSelf);
///   return fetch();
/// });
/// ```
///
/// **Why each source self-heals instead of being refreshed from outside.** The alternative was one
/// cross-feature `refreshEligibility()` that invalidated programs, scholars, and attendance
/// together. That could not be placed anywhere without an import cycle (attendance already imports
/// programs), and it put the responsibility for a provider's freshness on every screen that happens
/// to render it — which is exactly how `myProgramMembershipsProvider` ended up with **no**
/// invalidation path at all while four surfaces depended on it. Owning freshness at the source means
/// a new consumer inherits it for free and cannot forget.
///
/// Both triggers are best-effort. A missing realtime client (widget tests, or an unset
/// `API_BASE_URL`) degrades to resume-only rather than throwing; `realtimeClientProvider` reads
/// environment config on construction, so it can legitimately fail in a test harness.
void keepFresh(Ref ref, {required VoidCallback onStale}) {
  final observer = _ResumeObserver(onStale);
  WidgetsBinding.instance.addObserver(observer);

  StreamSubscription<void>? reconnectSub;
  try {
    reconnectSub = ref.watch(realtimeClientProvider).reconnected.listen((_) => onStale());
  } catch (_) {
    // Realtime unavailable — resume alone still corrects the common case.
  }

  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(observer);
    reconnectSub?.cancel();
  });
}

class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive`/`hidden` fire for transient interruptions (notification shade, app switcher) that
    // never invalidate anything, so only a real foreground transition triggers a refetch.
    if (state == AppLifecycleState.resumed) onResume();
  }
}

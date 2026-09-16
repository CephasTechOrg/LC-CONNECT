import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import 'app_router.dart';

/// A navigation a notification tap asked for, deferred until the app can actually perform it.
///
/// Takes the router rather than a location string so a queued open keeps whatever `extra` it
/// needed (a preloaded `MessageThread`, `GroupChatArgs`) and so the decision of *where* to go can
/// be made at drain time — when the thread list is far more likely to be loaded than it was during
/// a cold start.
typedef DeepLinkOpen = void Function(GoRouter router);

/// Single-slot queue for a pending notification open.
///
/// Why a queue at all: `notificationRegistrarProvider` used to `push()` the moment the auth state
/// carried a user, but the router's `redirect` then evaluated that pushed location against gates
/// that had not resolved yet. A tap during a cold start was silently discarded — bounced to
/// `/login` while the session was still restoring, or to `/verify-email`, `/accept-policies`, or
/// `/onboarding`. The user saw their notification "do nothing".
///
/// Single-slot on purpose: if two notifications are tapped before the app is ready, the second is
/// the one the user most recently chose, so it wins.
final pendingDeepLinkProvider =
    NotifierProvider<PendingDeepLinkNotifier, DeepLinkOpen?>(PendingDeepLinkNotifier.new);

class PendingDeepLinkNotifier extends Notifier<DeepLinkOpen?> {
  @override
  DeepLinkOpen? build() => null;

  void enqueue(DeepLinkOpen open) => state = open;

  /// Returns the queued open and clears the slot, so it can never run twice.
  DeepLinkOpen? take() {
    final open = state;
    if (open != null) state = null;
    return open;
  }
}

/// Whether a pushed route would survive the router's redirect gates.
///
/// Mirrors the conditions in `app_router.dart`'s `redirect`: anything short of a restored,
/// signed-in, verified, policy-accepted, onboarded account will be redirected somewhere else, and
/// pushing into that is how the tap got lost in the first place.
bool _canNavigate(Ref ref) {
  if (!ref.read(authNotifierProvider.notifier).sessionRestored) return false;
  if (ref.read(suspendedSessionProvider) != null) return false;
  final user = ref.read(authNotifierProvider).asData?.value;
  if (user == null) return false;
  return user.isVerified && user.policiesAccepted && user.profileCompleted;
}

/// Drains [pendingDeepLinkProvider] as soon as the app becomes navigable. Watch once at the root.
///
/// Reacts to both inputs: a tap arriving while the app is already running (drain immediately) and
/// a tap queued during startup that becomes performable when the restore finishes.
final deepLinkDrainProvider = Provider<void>((ref) {
  void drain() {
    if (ref.read(pendingDeepLinkProvider) == null) return;
    if (!_canNavigate(ref)) return;
    final open = ref.read(pendingDeepLinkProvider.notifier).take();
    if (open == null) return;
    // Off the current frame: this runs from a provider listener, and navigating synchronously
    // during a build or a redirect evaluation is what produced the `!_debugLocked` navigator
    // crashes documented in app_router.dart.
    Future<void>.microtask(() => open(ref.read(routerProvider)));
  }

  ref.listen(authNotifierProvider, (_, _) => drain());
  ref.listen(suspendedSessionProvider, (_, _) => drain());
  ref.listen(pendingDeepLinkProvider, (_, _) => drain(), fireImmediately: true);
});

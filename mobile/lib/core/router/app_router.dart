import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_routes.dart';
import '../../features/auth/providers/auth_provider.dart';

// Notifies GoRouter whenever auth state changes so redirect re-evaluates.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(this._ref) {
    _ref.listen<AsyncValue<AuthUser?>>(
      authNotifierProvider,
      (prev, next) => notifyListeners(),
    );
    _ref.listen<SuspendedSession?>(
      suspendedSessionProvider,
      (prev, next) => notifyListeners(),
    );
  }

  final Ref _ref;

  bool get isLoggedIn =>
      _ref.read(authNotifierProvider).asData?.value != null;

  bool get isSuspended => _ref.read(suspendedSessionProvider) != null;

  bool get isVerified =>
      _ref.read(authNotifierProvider).asData?.value?.isVerified ?? false;

  bool get policiesAccepted =>
      _ref.read(authNotifierProvider).asData?.value?.policiesAccepted ?? false;

  bool get profileCompleted =>
      _ref.read(authNotifierProvider).asData?.value?.profileCompleted ?? false;

  bool get awaitingEmailConfirmation =>
      _ref.read(authNotifierProvider.notifier).awaitingEmailConfirmation;

  /// Whether the one-time session restore has finished. Until it has, "not logged in" is unknown
  /// rather than false — see [sessionRestored] on `AuthNotifier`.
  bool get sessionRestored => _ref.read(authNotifierProvider.notifier).sessionRestored;
}

/// The complete routing gate, as a pure function.
///
/// Extracted from [routerProvider] so it can be unit-tested. Every branch here decides whether a
/// user in a given auth state may sit at a given location, which makes it the most
/// safety-critical logic in the app — a mistake either strands someone on a screen they cannot
/// leave or lets them past the email-confirmation, policy-acceptance, or onboarding gates. Driving
/// it through a mounted router instead needs an initialised Supabase instance and every provider
/// the destination screen touches, so in practice it went untested.
///
/// Returns the location to redirect to, or `null` to stay put.
@visibleForTesting
String? resolveRedirect({
  required String loc,
  required bool sessionRestored,
  required bool isLoggedIn,
  required bool isSuspended,
  required bool isVerified,
  required bool policiesAccepted,
  required bool profileCompleted,
  required bool awaitingEmailConfirmation,
}) {
    // Screens accessible without a session
    final isPublicScreen = loc == '/login' ||
        loc == '/register' ||
        loc == '/forgot-password' ||
        loc == '/reset-password';
    final isVerifyScreen = loc == '/verify-email';
    final isPolicyGate = loc == '/accept-policies';
    final isOnboarding = loc == '/onboarding';
    final isSuspendedScreen = loc == '/suspended';
    final isSplash = loc == '/splash';

    // A policy document is readable in every state: with no account (the signup checkbox links
    // into it), while suspended, at the acceptance gate, or from Settings. Never redirect away
    // from one — it was briefly in `isPublicScreen`, which made the "verified user on a public
    // screen → move forward" rule below throw a signed-in reader out to /home mid-document.
    if (loc.startsWith('/policies/')) return null;

    // Session restore still in flight. Every rule below asks "is this user allowed here?",
    // and none of them can be answered yet: `isLoggedIn` is false only because the answer has
    // not arrived. Holding on the splash is what stops an authenticated user being shown the
    // login form (and stops a notification deep link being bounced to it).
    if (!sessionRestored) return isSplash ? null : '/splash';

    // Suspended account — keep Supabase session so user can appeal; block the rest of the app.
    if (isSuspended) {
      if (!isSuspendedScreen) return '/suspended';
      return null;
    }
    if (!isSuspended && isSuspendedScreen) return '/login';

    // Pending Supabase email confirmation — only verify + login (back/cancel path).
    if (!isLoggedIn && awaitingEmailConfirmation) {
      if (isVerifyScreen || loc == '/login') return null;
      return '/verify-email';
    }

    // Not logged in — only public screens allowed
    if (!isLoggedIn && !isPublicScreen) return '/login';

    // Logged in but not verified — allow verify + logout path to login/register
    if (isLoggedIn && !isVerified) {
      if (isVerifyScreen || isPublicScreen) return null;
      return '/verify-email';
    }
    // Verified but has not accepted the current policies — nothing else is reachable. Comes
    // before the "move forward" rules below so a stale acceptance cannot be skipped by landing
    // on /login or /verify-email. The gate's own Sign out is the way out.
    if (isLoggedIn && isVerified && !policiesAccepted) {
      return isPolicyGate ? null : '/accept-policies';
    }
    // Accepted, so the gate is behind them.
    if (isLoggedIn && isVerified && isPolicyGate) {
      return profileCompleted ? '/home' : '/onboarding';
    }

    // Logged in + verified on a public, verify, or splash screen → move forward.
    // `isSplash` is included so a restored session leaves the splash by the same ladder every
    // other entry point uses, rather than needing the whole gate sequence duplicated here.
    if (isLoggedIn && isVerified && (isPublicScreen || isVerifyScreen || isSplash)) {
      return profileCompleted ? '/home' : '/onboarding';
    }

    // Verified, profile incomplete, not yet on onboarding
    if (isLoggedIn && isVerified && !profileCompleted && !isOnboarding) {
      return '/onboarding';
    }

    // Profile complete but still sitting on onboarding
    if (isLoggedIn && isVerified && profileCompleted && isOnboarding) {
      return '/home';
    }

    return null;
}

/// Clears text-field focus on every route change.
///
/// Beta report #16: the keyboard stayed up after onboarding and appeared over the dashboard, which
/// has no input at all. The cause is that onboarding does not *navigate* — it completes by calling
/// `refreshProfile()`, which changes the auth state, which fires `refreshListenable`, and the
/// redirect swaps `/onboarding` for `/home`. **A redirect-driven route swap does not dismiss the
/// keyboard**, and `unfocus` appeared nowhere in the app outside one widget.
///
/// An observer covers it once, for every transition — push, pop and replace — including the
/// redirect-driven ones no per-screen `dispose()` can catch.
class _UnfocusOnNavigate extends NavigatorObserver {
  void _unfocus() {
    // `unfocus` rather than focusing a throwaway node: the latter leaves an orphan in the tree and
    // can re-open the keyboard on the next rebuild (see DismissKeyboardOnTap).
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _unfocus();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _unfocus();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _unfocus();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _unfocus();
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    // Launch → Splash → restore → App | Login. Launching at '/login' meant the login form
    // doubled as the loading screen for every returning user; see [SplashScreen].
    initialLocation: '/splash',
    refreshListenable: notifier,
    observers: [_UnfocusOnNavigate()],
    redirect: (context, state) => resolveRedirect(
      loc: state.matchedLocation,
      sessionRestored: notifier.sessionRestored,
      isLoggedIn: notifier.isLoggedIn,
      isSuspended: notifier.isSuspended,
      isVerified: notifier.isVerified,
      policiesAccepted: notifier.policiesAccepted,
      profileCompleted: notifier.profileCompleted,
      awaitingEmailConfirmation: notifier.awaitingEmailConfirmation,
    ),
    routes: appRoutes(),
  );
});

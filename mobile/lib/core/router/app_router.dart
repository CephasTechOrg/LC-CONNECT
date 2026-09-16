import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import '../../features/auth/screens/suspended_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/campus_hub/screens/campus_hub_screen.dart';
import '../../features/campus_hub/screens/campus_directory_screen.dart';
import '../../features/campus_hub/screens/campus_position_detail_screen.dart';
import '../../features/campus_hub/screens/campus_updates_screen.dart';
import '../../features/campus_hub/screens/campus_opportunities_screen.dart';
import '../../features/campus_hub/screens/campus_post_detail_screen.dart';
import '../../features/campus_hub/screens/campus_resources_screen.dart';
import '../../features/campus_hub/screens/compose_campus_post_screen.dart';
import '../../features/campus_hub/screens/my_campus_posts_screen.dart';
import '../../features/campus_hub/providers/campus_publishing_provider.dart';
import '../../features/discovery/screens/discovery_screen.dart';
import '../../features/activities/screens/activities_screen.dart';
import '../../features/activities/screens/activity_detail_screen.dart';
import '../../features/activities/screens/create_activity_screen.dart';
import '../../features/activities/providers/activities_provider.dart';
import '../../features/messages/screens/chat_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/messages/screens/new_message_screen.dart';
import '../../features/messages/providers/messages_provider.dart';
import '../../features/groups/data/group_models.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/campus_positions/screens/edit_campus_position_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/public_profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/scholars/screens/blueprint_bond_screen.dart';
import '../../features/attendance/screens/attendance_scanner_screen.dart';
import '../../features/connections/screens/connections_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/policies/screens/policy_document_screen.dart';
import '../../features/policies/screens/policy_gate_screen.dart';
import '../../shared/widgets/nav_shell.dart';

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
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) =>
            ResetPasswordScreen(email: state.extra as String?),
      ),
      GoRoute(path: '/verify-email', builder: (context, state) => const VerifyEmailScreen()),
      GoRoute(path: '/suspended', builder: (context, state) => const SuspendedScreen()),
      GoRoute(
        path: '/accept-policies',
        builder: (context, state) => const PolicyGateScreen(),
      ),
      GoRoute(
        path: '/policies/:slug',
        builder: (context, state) =>
            PolicyDocumentScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(
        path: '/users/:profileId',
        builder: (context, state) => PublicProfileScreen(
          profileId: state.pathParameters['profileId']!,
          preloadedName: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/groups/:groupId',
        builder: (context, state) =>
            GroupDetailScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      // Top-level (not in the shell): a pushed detail screen with its own back button, reachable
      // from anywhere — including the top-level notification center. Keeping it inside the shell
      // made cross-navigator pushes lock the navigator (the '!_debugLocked' crash).
      GoRoute(
        path: '/connections',
        builder: (context, state) => const ConnectionsScreen(),
      ),
      // Same reasoning as '/connections' above: reachable from the top-level notification center
      // (the Blueprint Bond completion nudge), so it cannot live inside the shell. It used to,
      // which surfaced as the app appearing to sign out when tapping that notification — the
      // navigator-lock crash unwound the whole route stack back to '/login'-adjacent state rather
      // than a real session loss.
      GoRoute(
        path: '/profile/blueprint-bond',
        builder: (context, state) => const BlueprintBondScreen(),
      ),
      // Top-level scanner route — opened from push notifications and the Campus Hub card.
      GoRoute(
        path: '/attendance/scan',
        // `?session=` is carried from the push payload so a tap on a stale notification can say
        // *which* session closed instead of a bare "Attendance is closed".
        builder: (context, state) => AttendanceScannerScreen(
          sessionId: state.uri.queryParameters['session'],
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => NavShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const CampusHubScreen(),
            routes: [
              GoRoute(
                path: 'updates',
                builder: (context, state) => const CampusUpdatesScreen(),
              ),
              GoRoute(
                path: 'opportunities',
                builder: (context, state) => const CampusOpportunitiesScreen(),
              ),
              GoRoute(
                path: 'resources',
                builder: (context, state) => const CampusResourcesScreen(),
              ),
              GoRoute(
                path: 'my-posts',
                builder: (context, state) => const MyCampusPostsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    // `extra` carries an AuthorCampusPost when editing; null when creating.
                    builder: (context, state) => ComposeCampusPostScreen(
                      existing: state.extra as AuthorCampusPost?,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'posts/:postId',
                builder: (context, state) => CampusPostDetailScreen(
                  postId: state.pathParameters['postId']!,
                ),
              ),
              GoRoute(
                path: 'directory',
                builder: (context, state) => const CampusDirectoryScreen(),
                routes: [
                  GoRoute(
                    path: ':positionId',
                    builder: (context, state) => CampusPositionDetailScreen(
                      positionId: state.pathParameters['positionId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(path: '/discover', builder: (context, state) => const DiscoveryScreen()),
          GoRoute(
            path: '/activities',
            builder: (context, state) => const ActivitiesScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (context, state) => const CreateActivityScreen(),
              ),
              GoRoute(
                path: ':activityId',
                builder: (context, state) => ActivityDetailScreen(
                  activity: state.extra as Activity,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/messages',
            builder: (context, state) => const MessagesScreen(),
            routes: [
              GoRoute(
                // Static segment — must come before :matchId below so it isn't swallowed by it.
                path: 'new',
                builder: (context, state) => const NewMessageScreen(),
              ),
              GoRoute(
                // Two segments, so it never collides with the single-segment :matchId below.
                path: 'group/:conversationId',
                builder: (context, state) {
                  final args = state.extra as GroupChatArgs?;
                  return ChatScreen(
                    matchId: state.pathParameters['conversationId']!,
                    groupTitle: args?.name ?? 'Group',
                    groupId: args?.groupId,
                    groupAvatarUrl: args?.avatarUrl,
                  );
                },
              ),
              GoRoute(
                path: ':matchId',
                builder: (context, state) => ChatScreen(
                  matchId: state.pathParameters['matchId']!,
                  thread: state.extra as MessageThread?,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => const EditProfileScreen(),
              ),
              GoRoute(
                path: 'campus-position',
                builder: (context, state) => const EditCampusPositionScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

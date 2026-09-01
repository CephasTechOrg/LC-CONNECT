import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
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

  bool get profileCompleted =>
      _ref.read(authNotifierProvider).asData?.value?.profileCompleted ?? false;

  bool get awaitingEmailConfirmation =>
      _ref.read(authNotifierProvider.notifier).awaitingEmailConfirmation;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      final isLoggedIn = notifier.isLoggedIn;
      final isSuspended = notifier.isSuspended;
      final isVerified = notifier.isVerified;
      final profileCompleted = notifier.profileCompleted;
      final awaitingEmailConfirmation = notifier.awaitingEmailConfirmation;
      final loc = state.matchedLocation;

      // Screens accessible without a session
      final isPublicScreen = loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password' ||
          loc == '/reset-password';
      final isVerifyScreen = loc == '/verify-email';
      final isOnboarding = loc == '/onboarding';
      final isSuspendedScreen = loc == '/suspended';

      // Suspended account — keep Supabase session so user can appeal; block the rest of the app.
      if (isSuspended) {
        if (!isSuspendedScreen) return '/suspended';
        return null;
      }
      if (!isSuspended && isSuspendedScreen) return '/login';

      // Pending Supabase email confirmation — allow verify + public auth screens
      // so the user can go back to login/register after canceling.
      if (!isLoggedIn && awaitingEmailConfirmation) {
        if (isVerifyScreen || isPublicScreen) return null;
        return '/verify-email';
      }

      // Not logged in — only public screens allowed
      if (!isLoggedIn && !isPublicScreen) return '/login';

      // Logged in but not verified — allow verify + logout path to login/register
      if (isLoggedIn && !isVerified) {
        if (isVerifyScreen || isPublicScreen) return null;
        return '/verify-email';
      }
      // Logged in + verified on a public or verify screen → move forward
      if (isLoggedIn && isVerified && (isPublicScreen || isVerifyScreen)) {
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
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) =>
            ResetPasswordScreen(email: state.extra as String),
      ),
      GoRoute(path: '/verify-email', builder: (context, state) => const VerifyEmailScreen()),
      GoRoute(path: '/suspended', builder: (context, state) => const SuspendedScreen()),
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
        builder: (context, state) => const AttendanceScannerScreen(),
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

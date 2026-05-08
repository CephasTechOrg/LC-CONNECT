import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/discovery/screens/discovery_screen.dart';
import '../../features/activities/screens/activities_screen.dart';
import '../../features/activities/screens/activity_detail_screen.dart';
import '../../features/activities/screens/create_activity_screen.dart';
import '../../features/activities/providers/activities_provider.dart';
import '../../features/messages/screens/chat_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/messages/providers/messages_provider.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/public_profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
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
  }

  final Ref _ref;

  bool get isLoggedIn =>
      _ref.read(authNotifierProvider).asData?.value != null;

  bool get isVerified =>
      _ref.read(authNotifierProvider).asData?.value?.isVerified ?? false;

  bool get profileCompleted =>
      _ref.read(authNotifierProvider).asData?.value?.profileCompleted ?? false;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      final isLoggedIn = notifier.isLoggedIn;
      final isVerified = notifier.isVerified;
      final profileCompleted = notifier.profileCompleted;
      final loc = state.matchedLocation;

      // Screens accessible without a session
      final isPublicScreen = loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password' ||
          loc == '/reset-password';
      final isVerifyScreen = loc == '/verify-email';
      final isOnboarding = loc == '/onboarding';

      // Not logged in — only public screens allowed
      if (!isLoggedIn && !isPublicScreen) return '/login';

      // Logged in but not verified — gate to verify-email only
      if (isLoggedIn && !isVerified && !isVerifyScreen) return '/verify-email';

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
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(
        path: '/users/:profileId',
        builder: (context, state) => PublicProfileScreen(
          profileId: state.pathParameters['profileId']!,
          preloadedName: state.extra as String?,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => NavShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          GoRoute(path: '/connections', builder: (context, state) => const ConnectionsScreen()),
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
            ],
          ),
        ],
      ),
    ],
  );
});

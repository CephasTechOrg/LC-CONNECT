import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/discovery/screens/discovery_screen.dart';
import '../../features/activities/screens/activities_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
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
      final profileCompleted = notifier.profileCompleted;
      final loc = state.matchedLocation;

      final onAuthScreen = loc == '/login' || loc == '/register';
      final onOnboarding = loc == '/onboarding';

      // Not logged in — force to login
      if (!isLoggedIn && !onAuthScreen) return '/login';

      // Logged in + on an auth screen → route based on profile state
      if (isLoggedIn && onAuthScreen) {
        return profileCompleted ? '/home' : '/onboarding';
      }

      // Logged in, profile incomplete, not already on onboarding
      if (isLoggedIn && !profileCompleted && !onOnboarding) return '/onboarding';

      // Profile complete but still sitting on onboarding screen
      if (isLoggedIn && profileCompleted && onOnboarding) return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      ShellRoute(
        builder: (context, state, child) => NavShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          GoRoute(path: '/connections', builder: (context, state) => const ConnectionsScreen()),
          GoRoute(path: '/discover', builder: (context, state) => const DiscoveryScreen()),
          GoRoute(path: '/activities', builder: (context, state) => const ActivitiesScreen()),
          GoRoute(path: '/messages', builder: (context, state) => const MessagesScreen()),
          GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

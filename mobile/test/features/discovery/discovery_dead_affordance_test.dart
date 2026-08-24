import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/discovery/providers/discovery_provider.dart';
import 'package:lc_connect/features/discovery/screens/discovery_screen.dart';
import 'package:lc_connect/features/notifications/providers/notifications_provider.dart';

class _MockAuthNotifier extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'user-1',
        email: 'student@students.livingstone.edu',
        role: 'student',
        profileCompleted: true,
        isVerified: true,
      );
}

class _MockDiscoveryNotifier extends DiscoveryNotifier {
  @override
  Future<List<DiscoveryCard>> build() async => const [];
}

class _MockNotificationCount extends NotificationCountNotifier {
  @override
  int build() => 0;
}

Widget _discoveryScope() {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const DiscoveryScreen()),
    ],
  );
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_MockAuthNotifier.new),
      discoveryNotifierProvider.overrideWith(_MockDiscoveryNotifier.new),
      notificationCountProvider.overrideWith(_MockNotificationCount.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('DiscoveryScreen dead-affordance guards', () {
    testWidgets('search bar has no tune / advanced-filter icon', (tester) async {
      await tester.pumpWidget(_discoveryScope());
      await tester.pumpAndSettle();

      // Filters are chips only — the old tune icon was a no-op false affordance.
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.text('All'), findsOneWidget); // filter chip row still present
    });
  });
}

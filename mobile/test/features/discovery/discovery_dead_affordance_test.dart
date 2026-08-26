import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/connections/providers/connections_provider.dart';
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

class _MockConnectionsNotifier extends ConnectionsNotifier {
  _MockConnectionsNotifier([this.incoming = const []]);
  final List<ConnectionRequest> incoming;

  @override
  Future<ConnectionsState> build() async =>
      ConnectionsState(incoming: incoming, outgoing: const []);
}

Widget _discoveryScope({List<ConnectionRequest> incoming = const []}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const DiscoveryScreen()),
      GoRoute(path: '/connections', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/notifications', builder: (_, _) => const SizedBox()),
    ],
  );
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_MockAuthNotifier.new),
      discoveryNotifierProvider.overrideWith(_MockDiscoveryNotifier.new),
      notificationCountProvider.overrideWith(_MockNotificationCount.new),
      connectionsNotifierProvider.overrideWith(
        () => _MockConnectionsNotifier(incoming),
      ),
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

    testWidgets('header exposes connection requests entry with badge', (tester) async {
      final req = ConnectionRequest(
        id: 'req-1',
        senderId: 'u1',
        receiverId: 'me',
        status: 'pending',
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(_discoveryScope(incoming: [req, req]));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_add_alt_1_outlined), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/connections/providers/connections_provider.dart';
import 'package:lc_connect/features/messages/providers/unread_provider.dart';
import 'package:lc_connect/shared/widgets/nav_shell.dart';

class _RoleAuth extends AuthNotifier {
  _RoleAuth(this.role);
  final String role;

  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'user-1',
        email: 'u@students.livingstone.edu',
        role: role,
        profileCompleted: true,
        isVerified: true,
      );
}

class _MockUnread extends UnreadNotifier {
  @override
  UnreadState build() => const UnreadState();
}

class _MockConnections extends ConnectionsNotifier {
  _MockConnections(this.incoming);
  final List<ConnectionRequest> incoming;

  @override
  Future<ConnectionsState> build() async =>
      ConnectionsState(incoming: incoming, outgoing: const []);
}

ConnectionRequest _req(String id) => ConnectionRequest(
      id: id,
      senderId: 'sender',
      receiverId: 'user-1',
      status: 'pending',
      createdAt: DateTime.now(),
    );

Widget _app({
  required String role,
  List<ConnectionRequest> incoming = const [],
  String initialLocation = '/discover',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => NavShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
          GoRoute(path: '/discover', builder: (_, _) => const Text('discover')),
          GoRoute(path: '/activities', builder: (_, _) => const Text('activities')),
          GoRoute(path: '/messages', builder: (_, _) => const Text('messages')),
          GoRoute(path: '/profile', builder: (_, _) => const Text('profile')),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _RoleAuth(role)),
      unreadProvider.overrideWith(_MockUnread.new),
      connectionsNotifierProvider.overrideWith(() => _MockConnections(incoming)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('NavShell Connect badge (#11)', () {
    testWidgets('student Connect tab shows incoming request count', (tester) async {
      await tester.pumpWidget(
        _app(role: 'student', incoming: [_req('1'), _req('2')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byType(Badge), findsWidgets);
    });

    testWidgets('student Connect tab has no badge when inbox empty', (tester) async {
      await tester.pumpWidget(_app(role: 'student', incoming: const []));
      await tester.pumpAndSettle();

      expect(find.text('Connect'), findsOneWidget);
      // No numeric badge label for connections (Messages unread is also 0).
      expect(find.text('0'), findsNothing);
    });

    testWidgets('staff Students tab never shows connection-request badge', (tester) async {
      await tester.pumpWidget(
        _app(role: 'staff', incoming: [_req('1'), _req('2'), _req('3')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      // Staff browse tab must not surface student matching request counts.
      expect(find.text('3'), findsNothing);
    });
  });
}

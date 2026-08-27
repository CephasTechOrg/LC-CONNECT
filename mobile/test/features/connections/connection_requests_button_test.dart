import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/connections/providers/connections_provider.dart';
import 'package:lc_connect/features/connections/widgets/connection_requests_button.dart';

class _MockConnections extends ConnectionsNotifier {
  _MockConnections(this.incoming);
  final List<ConnectionRequest> incoming;

  @override
  Future<ConnectionsState> build() async =>
      ConnectionsState(incoming: incoming, outgoing: const []);
}

void main() {
  testWidgets('ConnectionRequestsButton navigates to /connections', (tester) async {
    var pushed = false;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: ConnectionRequestsButton(),
          ),
        ),
        GoRoute(
          path: '/connections',
          builder: (_, _) {
            pushed = true;
            return const Scaffold(body: Text('connections'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionsNotifierProvider.overrideWith(
            () => _MockConnections([
              ConnectionRequest(
                id: 'r1',
                senderId: 'a',
                receiverId: 'b',
                status: 'pending',
                createdAt: DateTime.now(),
              ),
            ]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byType(ConnectionRequestsButton));
    await tester.pumpAndSettle();

    expect(pushed, isTrue);
    expect(find.text('connections'), findsOneWidget);
  });
}

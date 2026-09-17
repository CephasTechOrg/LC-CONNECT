import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/messages/utils/chat_routes.dart';
import 'package:lc_connect/features/messages/widgets/messages_segments.dart';

/// The `Chats | Groups` switch (report #19).
void main() {
  /// A router with stub destinations, so the switch is tested rather than the two screens.
  Future<GoRouter> pumpSegments(WidgetTester tester, MessagesSegment active) async {
    final router = GoRouter(
      initialLocation: active.path,
      routes: [
        GoRoute(
          path: messagesPath,
          builder: (_, _) => Scaffold(
            body: Column(children: [
              const MessagesSegments(active: MessagesSegment.chats),
              const Text('chats body'),
            ]),
          ),
          routes: [
            GoRoute(
              path: 'groups',
              pageBuilder: (_, _) => const NoTransitionPage(
                child: Scaffold(
                  body: Column(children: [
                    MessagesSegments(active: MessagesSegment.groups),
                    Text('groups body'),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('tapping Groups navigates to the Groups route', (tester) async {
    final router = await pumpSegments(tester, MessagesSegment.chats);
    expect(find.text('chats body'), findsOneWidget);

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, groupsPath);
    expect(find.text('groups body'), findsOneWidget);
  });

  testWidgets('tapping Chats comes back', (tester) async {
    final router = await pumpSegments(tester, MessagesSegment.groups);
    expect(find.text('groups body'), findsOneWidget);

    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, messagesPath);
  });

  testWidgets('repeated switching does not pile up a back stack', (tester) async {
    // The switch navigates with `go`, not `push`. With `push`, four taps would leave four pages
    // stacked and the back button would walk down through alternating Chats and Groups.
    final router = await pumpSegments(tester, MessagesSegment.chats);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
    }

    expect(router.state.matchedLocation, messagesPath);
    // Chats is the hub's root, so there is nothing beneath it to pop back to.
    expect(router.routerDelegate.canPop(), isFalse);
  });

  testWidgets('the active segment does not re-navigate', (tester) async {
    // Tapping the segment you are already on would rebuild the thread list for nothing.
    await pumpSegments(tester, MessagesSegment.chats);
    final chats = tester.widget<InkWell>(
      find.ancestor(of: find.text('Chats'), matching: find.byType(InkWell)),
    );
    expect(chats.onTap, isNull);
  });

  testWidgets('the current segment is exposed to assistive technology', (tester) async {
    // Otherwise "which half am I on" is conveyed by fill colour alone.
    final handle = tester.ensureSemantics();
    await pumpSegments(tester, MessagesSegment.groups);

    expect(
      tester.getSemantics(find.text('Groups')),
      matchesSemantics(label: 'Groups', isSelected: true, isButton: true, hasSelectedState: true),
    );
    handle.dispose();
  });

  testWidgets('both segments meet the minimum tap target', (tester) async {
    await pumpSegments(tester, MessagesSegment.chats);
    for (final label in ['Chats', 'Groups']) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
      );
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });
}

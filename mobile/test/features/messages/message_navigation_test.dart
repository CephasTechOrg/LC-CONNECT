import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/groups/data/group_models.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';
import 'package:lc_connect/features/messages/utils/message_navigation.dart';

/// Opening a conversation from a notification has to decide DM vs group, and that decision was
/// made from the **already-loaded** inbox. On a cold start the inbox has not loaded, so a group
/// notification fell through to the DM route: right conversation, wrong screen — no group title,
/// no `groupId`, and every group affordance disabled.
///
/// The tap is now queued until the app is navigable, which usually means the list has loaded; and
/// when it still has not, the caller can supply a fetch instead of the code guessing.
void main() {
  const groupThread = MessageThread(
    conversationId: 'conv-group',
    kind: 'group',
    groupId: 'grp-1',
    groupName: 'Study Crew',
  );

  const dmThread = MessageThread(
    conversationId: 'conv-dm',
    kind: 'dm',
    matchId: 'match-1',
  );

  /// A router with stub destinations, so we assert routing rather than screen rendering.
  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/messages',
      routes: [
        GoRoute(path: '/messages', builder: (_, _) => const Text('inbox')),
        GoRoute(
          path: '/messages/group/:conversationId',
          builder: (_, _) => const Text('group chat'),
        ),
        GoRoute(path: '/messages/:matchId', builder: (_, _) => const Text('dm chat')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('a group conversation opens the group route when the inbox is loaded',
      (tester) async {
    final router = await pumpRouter(tester);

    openMessageConversation(
      router: router,
      conversationId: groupThread.addressingId,
      threads: const [groupThread],
    );
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/messages/group/conv-group');
    expect(router.state.extra, isA<GroupChatArgs>());
    expect((router.state.extra as GroupChatArgs).groupId, 'grp-1');
    expect((router.state.extra as GroupChatArgs).name, 'Study Crew');
  });

  testWidgets('a DM opens the DM route', (tester) async {
    final router = await pumpRouter(tester);

    openMessageConversation(
      router: router,
      conversationId: dmThread.addressingId,
      threads: const [dmThread],
    );
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/messages/match-1');
  });

  testWidgets('an unloaded inbox is fetched rather than assumed to be a DM', (tester) async {
    final router = await pumpRouter(tester);
    var fetched = 0;

    openMessageConversation(
      router: router,
      conversationId: groupThread.addressingId,
      threads: null, // the cold-start case
      onUnresolved: () async {
        fetched++;
        return const [groupThread];
      },
    );
    await tester.pumpAndSettle();

    expect(fetched, 1);
    // The regression: this used to land on '/messages/conv-group' as a DM.
    expect(router.state.matchedLocation, '/messages/group/conv-group');
  });

  testWidgets('a failed fetch still opens something rather than dropping the tap',
      (tester) async {
    final router = await pumpRouter(tester);

    openMessageConversation(
      router: router,
      conversationId: 'conv-unknown',
      threads: null,
      onUnresolved: () async => null,
    );
    await tester.pumpAndSettle();

    // Better a DM-shaped screen for the right conversation than a tap that does nothing.
    expect(router.state.matchedLocation, '/messages/conv-unknown');
  });

  testWidgets('with no resolver available it falls back immediately', (tester) async {
    final router = await pumpRouter(tester);

    openMessageConversation(router: router, conversationId: 'conv-x', threads: null);
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/messages/conv-x');
  });

  testWidgets('a conversation missing from a loaded inbox does not match another thread',
      (tester) async {
    final router = await pumpRouter(tester);

    openMessageConversation(
      router: router,
      conversationId: 'conv-absent',
      threads: const [groupThread, dmThread],
    );
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/messages/conv-absent');
  });
}

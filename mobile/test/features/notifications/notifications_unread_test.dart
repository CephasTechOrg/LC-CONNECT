import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/connections/providers/connections_provider.dart';
import 'package:lc_connect/features/notifications/data/notification_models.dart';
import 'package:lc_connect/features/notifications/providers/notifications_provider.dart';
import 'package:lc_connect/features/notifications/screens/notifications_screen.dart';

/// Beta report #14 — "notification read/unread state is not visually clear enough".
///
/// The unread chrome was fully implemented and completely unreachable. The screen marked
/// everything read on mount, which raced the list refetch, so rows could come back already read
/// and the styling would flash off; the workaround passed `treatAsRead: true` for every row, which
/// disabled unread styling on the only screen that lists notifications.
///
/// These tests pin the replacement: snapshot the unread ids on entry, style from the snapshot, and
/// mark rows read individually as they are opened.
void main() {
  AppNotification note(String id, {bool read = false}) => AppNotification(
        id: id,
        type: 'connection_request',
        read: read,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        actorName: 'Ama',
      );

  /// The screen renders a pinned "Connection requests" row that reads its own provider; stubbing
  /// it keeps these tests about notification state.
  ///
  /// Mounted through a real `GoRouter` with a stub destination, because opening a row navigates —
  /// a `MaterialApp(home:)` has no router in scope and the tap throws.
  Widget screen(List<AppNotification> items, {int badge = 1}) => ProviderScope(
        overrides: [
          notificationsListProvider.overrideWith(() => _FixedList(items)),
          connectionsNotifierProvider.overrideWith(_NoConnections.new),
          notificationCountProvider.overrideWith(() => _FixedCount(badge)),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/notifications',
            routes: [
              GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
              GoRoute(path: '/connections', builder: (_, _) => const Text('connections')),
            ],
          ),
        ),
      );

  testWidgets('unread rows are visibly unread on entry', (tester) async {
    await tester.pumpWidget(screen([note('n1'), note('n2', read: true)]));
    await tester.pumpAndSettle();

    // The tinted background is the visual cue; its presence is what the old code suppressed.
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    final tinted = tiles.where((t) => t.tileColor != null).length;
    expect(tinted, 1, reason: 'exactly the one unread row should be tinted');
  });

  testWidgets('unread is announced, not signalled by colour alone', (tester) async {
    await tester.pumpWidget(screen([note('n1')]));
    await tester.pumpAndSettle();

    // A tint and a dot are both colour — useless to a screen reader.
    expect(
      find.bySemanticsLabel(RegExp('^Unread\\. ')),
      findsOneWidget,
    );
  });

  testWidgets('an already-read row is not announced as unread', (tester) async {
    await tester.pumpWidget(screen([note('n1', read: true)]));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Unread\\. ')), findsNothing);
  });

  testWidgets('opening the screen does NOT mark everything read', (tester) async {
    await tester.pumpWidget(screen([note('n1'), note('n2')]));
    await tester.pumpAndSettle();

    // The regression: two unread rows must still look unread after mount settles.
    final tinted = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.tileColor != null)
        .length;
    expect(tinted, 2);
  });

  testWidgets('opening a row marks just that one read', (tester) async {
    final badge = _FixedCount(2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsListProvider.overrideWith(() => _FixedList([note('n1'), note('n2')])),
          connectionsNotifierProvider.overrideWith(_NoConnections.new),
          notificationCountProvider.overrideWith(() => badge),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/notifications',
            routes: [
              GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
              GoRoute(path: '/connections', builder: (_, _) => const Text('connections')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ama sent you a connection request').first);
    await tester.pumpAndSettle();

    // One row, not all of them — there is no per-row read call in the old design at all.
    expect(badge.markedRead, ['n1']);
    expect(badge.markAllCalls, 0);
  });

  testWidgets('a row opened and returned to still reads as one of the new ones', (tester) async {
    // Marking read must not retroactively restyle the list the user is still looking at —
    // that is the information ("these are the new ones") report #14 asked to preserve.
    await tester.pumpWidget(screen([note('n1'), note('n2')], badge: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ama sent you a connection request').first);
    await tester.pumpAndSettle();
    expect(find.text('connections'), findsOneWidget, reason: 'sanity: the tap navigated');

    // Back to the inbox — the screen was pushed over, not disposed, so the snapshot survives.
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();

    final tinted = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.tileColor != null)
        .length;
    expect(tinted, 2, reason: 'the entry snapshot governs styling, not the live read flag');
  });

  testWidgets('"Mark all read" appears only when something is unread', (tester) async {
    await tester.pumpWidget(screen([note('n1')], badge: 3));
    await tester.pumpAndSettle();
    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets('"Mark all read" is absent with a zero badge', (tester) async {
    await tester.pumpWidget(screen([note('n1', read: true)], badge: 0));
    await tester.pumpAndSettle();
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('"Mark all read" clears the unread styling it is asked to clear', (tester) async {
    await tester.pumpWidget(screen([note('n1'), note('n2')], badge: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    final tinted = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.tileColor != null)
        .length;
    expect(tinted, 0, reason: 'an explicit mark-all must take effect immediately');
  });

  testWidgets('an empty inbox says so', (tester) async {
    await tester.pumpWidget(screen(const []));
    await tester.pumpAndSettle();
    expect(find.text("You're all caught up."), findsOneWidget);
  });
}

class _NoConnections extends ConnectionsNotifier {
  @override
  Future<ConnectionsState> build() async =>
      const ConnectionsState(incoming: [], outgoing: []);
}

/// Badge stub. Overrides the mutators as well as [build]: the real ones POST to the API, and the
/// tap-driven tests below would otherwise reach Dio and a Supabase client that is not initialised
/// in a widget test.
class _FixedCount extends NotificationCountNotifier {
  _FixedCount(this._value);
  final int _value;

  /// Calls recorded so a test can assert the screen marked the right thing read.
  final List<String> markedRead = [];
  int markAllCalls = 0;

  @override
  int build() => _value;

  @override
  Future<void> markOneRead(String notificationId) async {
    markedRead.add(notificationId);
    if (state > 0) state = state - 1;
  }

  @override
  Future<void> markAllRead() async {
    markAllCalls++;
    state = 0;
  }
}

/// List stub. The real notifier fetches a page and self-heals; these tests supply fixed rows.
class _FixedList extends NotificationsListNotifier {
  _FixedList(this._rows);
  final List<AppNotification> _rows;

  @override
  Future<List<AppNotification>> build() async => _rows;

  @override
  Future<void> refresh() async => state = AsyncData(_rows);
}

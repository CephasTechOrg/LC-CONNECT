import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/groups/data/group_models.dart';
import 'package:lc_connect/features/groups/providers/groups_provider.dart';
import 'package:lc_connect/features/groups/widgets/groups_panel.dart';

/// The Groups panel stacks three lists: Pending invites, Your groups, and Discover. A public group
/// you've already joined (or been invited to) used to show in both its own section and Discover.
/// This pins the de-dupe at the widget level — it must not resurface.

GroupSummary _g(String name, {String? myStatus}) => GroupSummary(
      id: name,
      name: name,
      category: 'club',
      visibility: 'public',
      joinPolicy: 'open',
      memberCount: 3,
      myStatus: myStatus,
    );

Widget _panel(
  List<GroupSummary> discover, {
  List<GroupSummary> invites = const [],
  List<GroupSummary> Function(int page)? pages,
}) =>
    ProviderScope(
      overrides: [
        discoverGroupsProvider.overrideWith((ref, args) async => pages?.call(args.page) ?? discover),
        myGroupsProvider.overrideWith((ref) async => const <GroupSummary>[]),
        myInvitesProvider.overrideWith((ref) async => invites),
      ],
      child: const MaterialApp(home: Scaffold(body: GroupsPanel())),
    );

void main() {
  testWidgets('Discover hides groups you already belong to or were invited to', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_panel([
      _g('Joined Club', myStatus: 'active'),
      _g('Invited Club', myStatus: 'invited'),
      _g('Open Club'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Open Club'), findsOneWidget);
    expect(find.text('Joined Club'), findsNothing);
    expect(find.text('Invited Club'), findsNothing);
  });

  testWidgets('tells you when you are already in every discoverable group', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_panel([_g('Joined Club', myStatus: 'active')]));
    await tester.pumpAndSettle();

    expect(find.textContaining("in every group here"), findsOneWidget);
  });

  testWidgets('several invites collapse into one row', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_panel(
      [_g('Open Club')],
      invites: [_g('Debate', myStatus: 'invited'), _g('Choir', myStatus: 'invited')],
    ));
    await tester.pumpAndSettle();

    expect(find.text('2 group invites'), findsOneWidget);
    expect(find.text('Accept'), findsNothing, reason: 'the cards live in the sheet the row opens');
  });

  testWidgets('Discover loads one page at a time', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final first = [for (var i = 0; i < kDiscoverPageSize; i++) _g('Group $i')];
    await tester.pumpWidget(_panel(const [], pages: (p) => p == 0 ? first : [_g('Last Group')]));
    await tester.pumpAndSettle();
    expect(find.text('Last Group'), findsNothing);

    await tester.tap(find.text('Show more groups'));
    await tester.pumpAndSettle();
    expect(find.text('Last Group'), findsOneWidget);
    expect(find.text('Show more groups'), findsNothing, reason: 'a short page is the last one');
  });
}

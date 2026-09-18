import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/shared/widgets/a11y.dart';
import 'package:lc_connect/shared/widgets/app_filter_chip.dart';
import 'package:lc_connect/shared/widgets/app_skeleton.dart';
import 'package:lc_connect/shared/widgets/app_states.dart';

void main() {
  group('App skeleton (#17)', () {
    testWidgets('AppListSkeleton renders placeholder cards', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppListSkeleton(count: 2))),
      );
      expect(find.byType(AppSkeletonBox), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('AppProfileSkeleton renders without spinner', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppProfileSkeleton())),
      );
      expect(find.byType(AppSkeletonBox), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Accessibility helpers (#16)', () {
    testWidgets('AppAccessibleIconButton meets 48dp target', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppAccessibleIconButton(
              tooltip: 'Test action',
              onPressed: () {},
              icon: const Icon(Icons.star_outline),
            ),
          ),
        ),
      );

      final button = tester.getSize(find.byType(IconButton));
      expect(button.width, greaterThanOrEqualTo(kMinTouchTarget));
      expect(button.height, greaterThanOrEqualTo(kMinTouchTarget));
    });

    testWidgets('AppFilterChip exposes selected semantics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFilterChip(
              label: 'Study',
              selected: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(AppFilterChip), findsOneWidget);
      expect(tester.getSemantics(find.byType(AppFilterChip)).label, 'Study');
    });
  });

  /// Report #18's accessibility half (4.7) and the loading-vocabulary half (4.2).
  group('a loading state is announced, not just drawn', () {
    testWidgets('a skeleton group announces itself once, not per box', (tester) async {
      // The skeletons were silent: a screen-reader user heard nothing while a screen loaded,
      // which is indistinguishable from an empty screen. Announcing *per box* would be worse —
      // a list skeleton is twenty of them.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppThreadListSkeleton(count: 6))),
      );

      expect(find.bySemanticsLabel('Loading conversations'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the decorative boxes inside carry no semantics of their own', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppListSkeleton(count: 3))),
      );

      // One announcement for the group; the shapes are excluded.
      expect(find.bySemanticsLabel('Loading list'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a skeleton shimmers, so it reads as loading rather than failed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppSkeletonBox(height: 20))),
      );

      Gradient gradientNow() => (tester
              .widget<Container>(find.descendant(
                of: find.byType(AppSkeletonBox),
                matching: find.byType(Container),
              ))
              .decoration! as BoxDecoration)
          .gradient!;

      final before = gradientNow() as LinearGradient;
      await tester.pump(const Duration(milliseconds: 350));
      final after = gradientNow() as LinearGradient;

      expect(after.begin, isNot(before.begin), reason: 'the highlight should have moved');
    });

    testWidgets('reduced motion gets a static skeleton, not a frozen mid-flash', (tester) async {
      // Someone who asked the OS to reduce motion gets what this widget used to be for everyone.
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: Scaffold(body: AppSkeletonBox(height: 20))),
        ),
      );

      LinearGradient gradientNow() => (tester
              .widget<Container>(find.descendant(
                of: find.byType(AppSkeletonBox),
                matching: find.byType(Container),
              ))
              .decoration! as BoxDecoration)
          .gradient! as LinearGradient;

      final before = gradientNow();
      await tester.pump(const Duration(milliseconds: 700));
      expect(gradientNow().begin, before.begin, reason: 'it must not animate');
      // And it rests centred rather than part-way through a sweep.
      expect(before.begin, const Alignment(-1, 0));
    });
  });

  group('inline failure states', () {
    testWidgets('an inline message announces itself', (tester) async {
      // Three screens hand-rolled this and none of them announced anything: a screen-reader user
      // got silence where a sighted user got "Couldn't load this".
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppInlineMessage(message: "Couldn't load this", onRetry: () {}),
          ),
        ),
      );

      expect(find.bySemanticsLabel("Couldn't load this"), findsWidgets);
      handle.dispose();
    });

    testWidgets('Retry meets the minimum tap target', (tester) async {
      // A bare TextButton is shorter than 48dp, so the one actionable control in a failed state
      // was the hardest thing on screen to hit.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppInlineMessage(message: 'Failed', onRetry: () {}),
          ),
        ),
      );

      expect(tester.getSize(find.byType(TextButton)).height,
          greaterThanOrEqualTo(kMinTouchTarget));
    });

    testWidgets('no Retry is offered when there is nothing to retry', (tester) async {
      // Without a handler it is an empty state, not a failure — and a dead button is worse than
      // no button.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppInlineMessage(message: 'Nothing here'))),
      );

      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('an empty state can still be refreshed', () {
    testWidgets('AppScrollableEmptyState scrolls, so pull-to-refresh has something to pull',
        (tester) async {
      // The load-bearing part of the wrapper three screens each had their own copy of: a
      // RefreshIndicator over a non-scrollable child cannot be pulled at all, so an empty list
      // could never be refreshed.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppScrollableEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Nothing yet',
              subtitle: 'Check back soon',
            ),
          ),
        ),
      );

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.physics, isA<AlwaysScrollableScrollPhysics>());
      expect(find.text('Nothing yet'), findsOneWidget);
    });
  });
}

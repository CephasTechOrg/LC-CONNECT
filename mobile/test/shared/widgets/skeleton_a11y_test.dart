import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/shared/widgets/a11y.dart';
import 'package:lc_connect/shared/widgets/app_filter_chip.dart';
import 'package:lc_connect/shared/widgets/app_skeleton.dart';

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
}

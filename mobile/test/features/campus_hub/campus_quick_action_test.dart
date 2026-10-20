import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/screens/campus_hub_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, {int badgeCount = 0, VoidCallback? onTap}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          CampusQuickAction(
            icon: Icons.work_outline,
            label: 'Opportunities',
            badgeCount: badgeCount,
            onTap: onTap ?? () {},
          ),
        ]),
      ),
    ));
  }

  testWidgets('announces the new count with the label', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, badgeCount: 3);

    expect(find.bySemanticsLabel('Opportunities, 3 new'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('no badge and a plain label when nothing is new', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(find.bySemanticsLabel('Opportunities'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    handle.dispose();
  });

  testWidgets('caps the badge at 99+', (tester) async {
    await pump(tester, badgeCount: 150);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('the whole tile is a tap target of at least 48dp', (tester) async {
    var taps = 0;
    await pump(tester, onTap: () => taps++);

    final size = tester.getSize(find.byType(InkWell));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));

    await tester.tap(find.text('Opportunities'));
    expect(taps, 1);
  });
}

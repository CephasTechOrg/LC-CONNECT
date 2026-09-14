import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/onboarding/widgets/onboarding_shared_widgets.dart';

/// Pumps the grid with live state, so selecting really updates it.
Future<Set<String>> _pump(
  WidgetTester tester, {
  required List<String> options,
  int? max,
  bool custom = false,
}) async {
  final selected = <String>{};
  final extra = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => OnboardingChipGrid(
          options: [...options, ...extra],
          selected: selected,
          maxSelections: max,
          onAddCustom: custom
              ? (value) => setState(() {
                    extra.add(value);
                    selected.add(value);
                  })
              : null,
          onToggle: (v) => setState(() {
            selected.contains(v) ? selected.remove(v) : selected.add(v);
          }),
        ),
      ),
    ),
  ));
  await tester.pump();
  return selected;
}

const _many = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];

void main() {
  group('selection cap', () {
    testWidgets('five can be chosen', (tester) async {
      final selected = await _pump(tester, options: _many, max: kMaxSelections);
      for (final label in ['A', 'B', 'C', 'D', 'E']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(selected.length, 5);
    });

    testWidgets('a sixth is refused', (tester) async {
      final selected = await _pump(tester, options: _many, max: kMaxSelections);
      for (final label in ['A', 'B', 'C', 'D', 'E', 'F']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(selected.length, 5, reason: 'F must not be selectable at the cap');
      expect(selected.contains('F'), isFalse);
    });

    testWidgets('at the cap you can still swap one out', (tester) async {
      // Locking every chip at the limit would trap someone who picked wrong — only adding a
      // sixth is blocked, deselecting stays available.
      final selected = await _pump(tester, options: _many, max: kMaxSelections);
      for (final label in ['A', 'B', 'C', 'D', 'E']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      await tester.tap(find.text('A'));
      await tester.pump();
      expect(selected.contains('A'), isFalse);

      await tester.tap(find.text('F'));
      await tester.pump();
      expect(selected.contains('F'), isTrue, reason: 'a freed slot must be usable');
    });

    testWidgets('without a cap nothing is locked', (tester) async {
      final selected = await _pump(tester, options: _many);
      for (final label in _many) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(selected.length, _many.length);
    });
  });

  group('custom entries', () {
    testWidgets('a student can add something not on the list', (tester) async {
      final selected =
          await _pump(tester, options: ['Chess'], max: kMaxSelections, custom: true);

      await tester.tap(find.text('Add your own'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Afrobeats');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(selected.contains('Afrobeats'), isTrue);
      expect(find.text('Afrobeats'), findsOneWidget, reason: 'it should appear as a chip');
    });

    testWidgets('an empty entry adds nothing', (tester) async {
      final selected = await _pump(tester, options: ['Chess'], custom: true);
      await tester.tap(find.text('Add your own'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
    });

    testWidgets('the add affordance disappears at the cap', (tester) async {
      // Otherwise it invites you to type something that cannot be accepted.
      await _pump(tester, options: _many, max: kMaxSelections, custom: true);
      expect(find.text('Add your own'), findsOneWidget);
      for (final label in ['A', 'B', 'C', 'D', 'E']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(find.text('Add your own'), findsNothing);
    });

    testWidgets('no add affordance unless one is wired', (tester) async {
      await _pump(tester, options: ['Chess']);
      expect(find.text('Add your own'), findsNothing);
    });
  });
}

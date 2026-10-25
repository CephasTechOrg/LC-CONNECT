import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/shared/widgets/app_filter_chip.dart';

void main() {
  // The Compose post form lays its choices out in a Wrap. The chip's inner Align used to take the
  // full width there, so every option sat alone on its own centred line.
  testWidgets('chips in a Wrap share a line instead of each taking the full width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 393,
            child: Wrap(
              children: [
                AppFilterChip(label: 'Everyone', selected: true, onTap: () {}),
                AppFilterChip(label: 'Students', selected: false, onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    final first = tester.getRect(find.byType(AppFilterChip).first);
    final second = tester.getRect(find.byType(AppFilterChip).last);
    expect(first.width, lessThan(200));
    expect(second.top, first.top, reason: 'the second chip should sit beside the first');
  });
}

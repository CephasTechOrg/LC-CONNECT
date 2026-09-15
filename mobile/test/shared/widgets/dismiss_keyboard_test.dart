import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/shared/widgets/dismiss_keyboard.dart';

/// Wrapping a whole screen in a tap handler is easy to get wrong: too greedy and it eats the
/// taps meant for buttons and list rows. `HitTestBehavior.translucent` is what keeps it passive
/// — these tests pin that, because the failure mode (a dead Send button) is far worse than the
/// problem it solves.
///
/// Focus is asserted on the field's own node, not `primaryFocus`: after `unfocus()` the primary
/// focus becomes the root scope, which always reports `hasFocus == true`.
void main() {
  late FocusNode fieldFocus;

  setUp(() => fieldFocus = FocusNode());
  tearDown(() => fieldFocus.dispose());

  Widget harness({VoidCallback? onPressed}) {
    return MaterialApp(
      home: DismissKeyboardOnTap(
        child: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: fieldFocus, decoration: const InputDecoration(hintText: 'Message')),
              ElevatedButton(onPressed: onPressed ?? () {}, child: const Text('Send')),
              const SizedBox(key: Key('filler'), height: 300),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('a tap on empty space dismisses the keyboard', (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(fieldFocus.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('filler')));
    await tester.pumpAndSettle();
    expect(fieldFocus.hasFocus, isFalse, reason: 'tapping outside should hide the keyboard');
  });

  testWidgets('buttons underneath still receive their tap', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(harness(onPressed: () => pressed++));

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(pressed, 1, reason: 'the wrapper must not swallow taps meant for controls');
  });

  testWidgets('tapping the field itself keeps focus', (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(fieldFocus.hasFocus, isTrue,
        reason: 'focusing a field must not immediately unfocus it');
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/theme/app_theme.dart';
import 'package:lc_connect/shared/widgets/a11y.dart';

/// The two chat controls that were reachable in theory and not in practice.
void main() {
  group('Save in the edit sheet', () {
    // The app-wide `filledButtonTheme` sets `minimumSize: Size(double.infinity, 52)` because
    // nineteen of the twenty FilledButtons in this app are full-width form submits. The twentieth
    // is Save in the edit sheet, which sits in a Row next to Cancel. There the infinite minimum is
    // not a cosmetic overflow: layout throws "BoxConstraints forces an infinite width" and a
    // release build paints no button at all — the sheet let you type an edit and never save it.

    test('the call site overrides the theme minimum', () {
      // Asserted against the source because the sheet is a private widget inside a `part` file
      // and cannot be constructed directly. Coarse, but it fails if the override is dropped,
      // which is the regression that shipped.
      final source =
          File('lib/features/messages/widgets/chat_reactions.dart').readAsStringSync();
      final save = source.indexOf("Text('Save')");
      expect(save, greaterThan(-1), reason: 'the Save button is gone');

      final button = source.substring(save - 700, save);
      expect(button, contains('minimumSize'),
          reason: 'Save must override the full-width theme minimum or it will not lay out');
    });

    testWidgets('with that override it lays out on screen at a tappable size', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, kMinTouchTarget),
                  ),
                  onPressed: () {},
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      final screen = tester.getSize(find.byType(MaterialApp));
      expect(save.right, lessThanOrEqualTo(screen.width), reason: 'Save is off-screen');
      expect(save.height, greaterThanOrEqualTo(kMinTouchTarget));
    });
  });

  group('the send button', () {
    // Comments are stripped first: the fix carries an explanation that quotes the old code
    // verbatim, and a naive search would match the explanation and pass regardless.
    final source = File('lib/features/messages/widgets/chat_input.dart')
        .readAsStringSync()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    test('is never disabled by an earlier message still being in flight', () {
      // `sending` is true while *any* message in the thread is unacknowledged. On a cold backend
      // the first one stays that way for up to 60s, so `onTap: sending ? null : onSend` left the
      // button dead for a full minute. The tap then fell through to the app-level
      // DismissKeyboardOnTap — which is why the keyboard reacted when the button did not.
      expect(source, contains('onTap: onSend'));
      expect(source.contains('sending ? null : onSend'), isFalse,
          reason: 'a queued send must not block the next one — the outbox and the '
              'idempotent server already handle it');
    });

    test('has a hit area at the minimum tap target, not the 40px circle', () {
      // A near-miss on the old 40x40 target also fell through to the keyboard dismisser.
      expect(source, contains('width: kMinTouchTarget'));
      expect(source, contains('height: kMinTouchTarget'));
      expect(source, contains('HitTestBehavior.opaque'));
    });
  });
}

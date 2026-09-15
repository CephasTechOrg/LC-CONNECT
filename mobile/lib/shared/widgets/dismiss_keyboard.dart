import 'package:flutter/material.dart';

/// Dismisses the keyboard when the user taps anywhere that isn't interactive.
///
/// Without this, the only way off a focused text field is the platform's own gesture or leaving
/// the screen entirely — on the chat screen people were backing out of the conversation just to
/// see the messages behind the keyboard.
///
/// [HitTestBehavior.translucent] is the important part: this widget takes part in hit testing
/// but does not consume the gesture, so buttons, links and list taps inside still win. Only
/// taps that nothing else claims reach here.
class DismissKeyboardOnTap extends StatelessWidget {
  final Widget child;
  const DismissKeyboardOnTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // `unfocus` rather than `requestFocus(FocusNode())`: the latter leaves an orphan node in
      // the tree and can re-open the keyboard on the next rebuild.
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

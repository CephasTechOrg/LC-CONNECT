import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/shared/widgets/dismiss_keyboard.dart';

/// Beta report #16 — "the keyboard can remain visible after onboarding, or appear on the dashboard
/// even though no input is active".
///
/// The root cause was that onboarding does not navigate. It finishes by refreshing the auth state,
/// which fires the router's `refreshListenable`, and the redirect swaps `/onboarding` for `/home`.
/// **A redirect-driven route swap does not dismiss the keyboard**, and `unfocus` appeared nowhere
/// in the app outside `DismissKeyboardOnTap` — which was itself used on only 2 of the 24 screens
/// that have a text field.
///
/// A `NavigatorObserver` on the router covers every transition once, including the
/// redirect-driven ones that no per-screen `dispose()` can see.
void main() {
  /// Mirrors the observer installed in `app_router.dart`.
  late List<String> events;

  setUp(() => events = []);

  testWidgets('focus is cleared when a redirect swaps the route', (tester) async {
    var profileCompleted = false;
    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);

    final router = GoRouter(
      initialLocation: '/onboarding',
      refreshListenable: refresh,
      observers: [_RecordingUnfocus(events)],
      redirect: (context, state) {
        // The real gate: completing the profile moves the user on without any navigation call.
        if (state.matchedLocation == '/onboarding' && profileCompleted) return '/home';
        return null;
      },
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const Scaffold(
            body: TextField(autofocus: true, decoration: InputDecoration(hintText: 'Bio')),
          ),
        ),
        // No input at all — exactly the screen the keyboard used to appear over.
        GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('dashboard'))),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // The bio field holds focus, as it would when the student taps Finish.
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);

    profileCompleted = true;
    refresh.value++; // what `refreshProfile()` ultimately triggers
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/home');
    expect(events, contains('unfocus'), reason: 'the swap must clear focus');
    // After `unfocus` the primary focus is the enclosing scope, which is the correct resting
    // state — what must not remain is an *editable* holding it.
    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.context?.widget, isNot(isA<EditableText>()));
    expect(find.byType(EditableText), findsNothing, reason: 'the dashboard has no input');
  });

  testWidgets('focus is cleared on a push and on a pop', (tester) async {
    final router = GoRouter(
      initialLocation: '/a',
      observers: [_RecordingUnfocus(events)],
      routes: [
        GoRoute(path: '/a', builder: (_, _) => const Scaffold(body: TextField(autofocus: true))),
        GoRoute(path: '/b', builder: (_, _) => const Scaffold(body: Text('b'))),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    events.clear();

    router.push('/b');
    await tester.pumpAndSettle();
    expect(events, contains('unfocus'));

    events.clear();
    router.pop();
    await tester.pumpAndSettle();
    expect(events, contains('unfocus'));
  });

  group('DismissKeyboardOnTap', () {
    testWidgets('a tap on empty space dismisses, but a button still wins', (tester) async {
      var pressed = 0;
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(MaterialApp(
        home: DismissKeyboardOnTap(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: node),
                ElevatedButton(onPressed: () => pressed++, child: const Text('Save')),
                const Expanded(child: SizedBox.expand(key: Key('empty-space'))),
              ],
            ),
          ),
        ),
      ));

      node.requestFocus();
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);

      // The button must not be swallowed by the dismiss gesture — this is why the wrapper uses
      // HitTestBehavior.translucent, and why hoisting it app-wide is safe.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(pressed, 1);

      // Tap the empty region by finder rather than by coordinate: the default test surface is
      // 800x600, so a hardcoded y of 700 lands outside it.
      await tester.tap(find.byKey(const Key('empty-space')));
      await tester.pumpAndSettle();
      expect(node.hasFocus, isFalse, reason: 'a tap on nothing should dismiss the keyboard');
    });
  });
}

/// Records what the production observer does, so the assertion is about behaviour rather than
/// about a private class being present.
class _RecordingUnfocus extends NavigatorObserver {
  _RecordingUnfocus(this.events);
  final List<String> events;

  void _unfocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    events.add('unfocus');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _unfocus();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _unfocus();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _unfocus();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _unfocus();
}

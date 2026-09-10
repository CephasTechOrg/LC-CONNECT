import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:lc_connect/features/auth/screens/login_screen.dart';
import 'package:lc_connect/features/auth/screens/reset_password_screen.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/auth/widgets/auth_text_field.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => null;
}

Future<void> _pumpLogin(WidgetTester tester, Size size,
    {double textScale = 1.0, double bottomInset = 0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/register', builder: (c, s) => const Scaffold()),
    GoRoute(path: '/forgot-password', builder: (c, s) => const Scaffold()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [authNotifierProvider.overrideWith(_NoAuth.new)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: child!,
      ),
    ),
  ));
  await tester.pump();
}

/// Guards the three layout/crash defects found in the pre-pilot audit:
///   L1 — the login screen overflowed on small phones, at textScale 1.4, and with the keyboard up
///   F1 — validation errors were drawn on top of the value, inside a fixed-height field
///   R1 — /reset-password threw a null cast when reached without navigation state
void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test'));

  group('L1 login layout', () {
    final cases = {
      'iPhone 15 Pro 393x852': [const Size(393, 852), 1.0, 0.0],
      'small Android 360x640': [const Size(360, 640), 1.0, 0.0],
      'iPhone SE 320x568':     [const Size(320, 568), 1.0, 0.0],
      'landscape 852x393':     [const Size(852, 393), 1.0, 0.0],
      'tablet 834x1112':       [const Size(834, 1112), 1.0, 0.0],
      '360x640 textScale 1.4': [const Size(360, 640), 1.4, 0.0],
      '393x852 keyboard 336':  [const Size(393, 852), 1.0, 336.0],
      '360x640 keyboard 300':  [const Size(360, 640), 1.0, 300.0],
      '320x568 keyboard 280 @1.4': [const Size(320, 568), 1.4, 280.0],
    };
    cases.forEach((name, cfg) {
      testWidgets(name, (tester) async {
        await _pumpLogin(tester, cfg[0] as Size,
            textScale: cfg[1] as double, bottomInset: cfg[2] as double);
        final ex = tester.takeException();
        expect(ex, isNull, reason: name);
      });
    });
  });

  testWidgets('F1 error text no longer overlaps the value', (tester) async {
    final key = GlobalKey<FormState>();
    final ctrl = TextEditingController(text: 'typed value');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Form(
            key: key,
            child: AuthTextField(
              controller: ctrl,
              hintText: 'Confirm password',
              icon: Icons.lock_reset_rounded,
              validator: (v) => 'Passwords do not match',
            ),
          ),
        ),
      ),
    ));
    key.currentState!.validate();
    await tester.pump();

    final input = tester.renderObject<RenderBox>(find.text('typed value'));
    final err = tester.renderObject<RenderBox>(find.text('Passwords do not match'));
    final inputBottom = input.localToGlobal(Offset.zero).dy + input.size.height;
    final errTop = err.localToGlobal(Offset.zero).dy;
    expect(errTop, greaterThanOrEqualTo(inputBottom),
        reason: 'error must sit BELOW the value, not on top of it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('R1 reset route survives a null extra', (tester) async {
    final router = GoRouter(initialLocation: '/reset-password', routes: [
      GoRoute(
        path: '/reset-password',
        builder: (c, s) => ResetPasswordScreen(email: s.extra as String?),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [authNotifierProvider.overrideWith(_NoAuth.new)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    final ex = tester.takeException();
    expect(ex, isNull);
    // Falls back to asking for the email inline rather than crashing.
    expect(find.text('Enter your reset code'), findsOneWidget);
    expect(find.byType(AuthTextField), findsNWidgets(4));
  });
}

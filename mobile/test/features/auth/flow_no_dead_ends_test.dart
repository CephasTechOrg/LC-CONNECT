import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/screens/forgot_password_screen.dart';
import 'package:lc_connect/features/auth/screens/login_screen.dart';
import 'package:lc_connect/features/auth/screens/register_screen.dart';
import 'package:lc_connect/features/auth/screens/reset_password_screen.dart';
import 'package:lc_connect/features/auth/screens/verify_email_screen.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/onboarding/widgets/onboarding_shared_widgets.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => null;
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [authNotifierProvider.overrideWith(_NoAuth.new)],
    child: MaterialApp(home: screen),
  ));
  await tester.pump();
}

/// Every screen a user can be parked on must offer a visible way out. The router forces some of
/// these locations (unverified -> /verify-email, incomplete profile -> /onboarding), so a screen
/// without an exit is a screen the user cannot leave at all.
void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test'));

  testWidgets('verify-email offers a way back to login', (tester) async {
    await _pump(tester, const VerifyEmailScreen());
    expect(find.byTooltip('Back to login'), findsOneWidget);
    expect(find.text('Back to login'), findsOneWidget); // and a second, textual exit
  });

  testWidgets('verify-email can request a fresh code', (tester) async {
    await _pump(tester, const VerifyEmailScreen());
    expect(find.textContaining('Resend code', findRichText: true), findsOneWidget);
  });

  testWidgets('register offers a way back to login', (tester) async {
    await _pump(tester, const RegisterScreen());
    expect(find.byTooltip('Back to sign in'), findsOneWidget);
  });

  testWidgets('forgot-password offers both a way on and a way back', (tester) async {
    await _pump(tester, const ForgotPasswordScreen());
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Back to sign in'), findsOneWidget);
    // For someone who already holds a code but restarted the app.
    expect(find.text('I already have a code'), findsOneWidget);
  });

  testWidgets('reset-password can replace an expired code', (tester) async {
    await _pump(tester, const ResetPasswordScreen(email: 'a@students.livingstone.edu'));
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.textContaining('Send a new one', findRichText: true), findsOneWidget);
  });

  testWidgets('onboarding has a sign-out escape', (tester) async {
    // The router will not let a verified user leave /onboarding until the profile is complete,
    // so without this there is no exit from the app short of force-quitting.
    await _pump(tester, const Scaffold(body: OnboardingSignOutButton()));
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('login reaches both register and forgot-password', (tester) async {
    await _pump(tester, const LoginScreen());
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/auth/screens/register_screen.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => null;
}

/// Mirrors the real routes so `canPop()` behaves as it does in the app.
Future<void> _pumpApp(WidgetTester tester, {required String initial}) async {
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
      path: '/login',
      builder: (c, s) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => c.push('/register'),
            child: const Text('Create account'),
          ),
        ),
      ),
    ),
    GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [authNotifierProvider.overrideWith(_NoAuth.new)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

/// Asserts on what is actually on screen rather than on `currentConfiguration.uri`: an
/// imperative `push` adds a route match but leaves that URI reporting the base location, so it
/// says `/login` while RegisterScreen is the visible page.
void _expectOnRegister(WidgetTester tester, {required bool onRegister}) {
  expect(find.byType(RegisterScreen), onRegister ? findsOneWidget : findsNothing);
  expect(find.text('Create account'), onRegister ? findsNothing : findsOneWidget);
}

void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test'));

  group('register back navigation', () {
    testWidgets('the back arrow returns to login when pushed from it', (tester) async {
      // Login used to `go` here, which replaces rather than pushes — so there was nothing to go
      // back to, and Android's back gesture left the app entirely.
      await _pumpApp(tester, initial: '/login');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      _expectOnRegister(tester, onRegister: true);

      await tester.tap(find.byTooltip('Back to sign in'));
      await tester.pumpAndSettle();
      _expectOnRegister(tester, onRegister: false);
    });

    testWidgets('the back arrow still works when register is the entry point', (tester) async {
      // A deep link or a restart can land here with nothing to pop; the arrow must not be inert.
      await _pumpApp(tester, initial: '/register');
      _expectOnRegister(tester, onRegister: true);

      await tester.tap(find.byTooltip('Back to sign in'));
      await tester.pumpAndSettle();
      _expectOnRegister(tester, onRegister: false);
    });

    testWidgets('the system back gesture also returns to login', (tester) async {
      await _pumpApp(tester, initial: '/login');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      _expectOnRegister(tester, onRegister: true); // guards against passing vacuously

      // What Android's back gesture triggers.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      _expectOnRegister(tester, onRegister: false);
    });
  });
}

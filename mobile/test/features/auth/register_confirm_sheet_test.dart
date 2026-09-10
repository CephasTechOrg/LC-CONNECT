import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/auth/screens/register_screen.dart';

/// Records what reached `register()` without touching Supabase.
class _RecordingAuth extends AuthNotifier {
  static final calls = <String>[];

  @override
  Future<AuthUser?> build() async => null;

  @override
  Future<void> register(
    String email,
    String password, {
    required String contactEmail,
  }) async {
    calls.add('$email|$contactEmail');
  }
}

Future<void> _pumpRegister(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authNotifierProvider.overrideWith(_RecordingAuth.new)],
      child: const MaterialApp(home: RegisterScreen()),
    ),
  );
  await tester.pump();
}

/// Fills the four fields with values that pass the screen's own validators.
Future<void> _fillValidForm(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'John.Doe@students.livingstone.edu');
  await tester.enterText(fields.at(1), 'John.Doe@gmail.com');
  await tester.enterText(fields.at(2), 'hunter2pass');
  await tester.enterText(fields.at(3), 'hunter2pass');
  await tester.pump();
}

Future<void> _tapCreateAccount(WidgetTester tester) async {
  await tester.tap(find.text('Create Account'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test',
    );
  });

  setUp(_RecordingAuth.calls.clear);

  group('register confirm step', () {
    testWidgets('submitting opens the review sheet instead of registering', (tester) async {
      await _pumpRegister(tester);
      await _fillValidForm(tester);
      await _tapCreateAccount(tester);

      expect(find.text('Check your details'), findsOneWidget);
      // The whole point: nothing has been sent to Supabase yet.
      expect(_RecordingAuth.calls, isEmpty);
    });

    testWidgets('the sheet shows both addresses, normalised', (tester) async {
      await _pumpRegister(tester);
      await _fillValidForm(tester);
      await _tapCreateAccount(tester);

      // Lowercased, so what the user checks is exactly what the account is created with.
      expect(find.text('john.doe@students.livingstone.edu'), findsOneWidget);
      expect(find.text('john.doe@gmail.com'), findsOneWidget);
      expect(find.text("You'll sign in with"), findsOneWidget);
      expect(find.text('Your code will be sent to'), findsOneWidget);
    });

    testWidgets('Edit closes the sheet and registers nothing', (tester) async {
      await _pumpRegister(tester);
      await _fillValidForm(tester);
      await _tapCreateAccount(tester);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Check your details'), findsNothing);
      expect(_RecordingAuth.calls, isEmpty);
      // Back on the form with the typed values intact, ready to correct the typo.
      expect(find.text('John.Doe@students.livingstone.edu'), findsOneWidget);
    });

    testWidgets('confirming registers with the entered addresses', (tester) async {
      await _pumpRegister(tester);
      await _fillValidForm(tester);
      await _tapCreateAccount(tester);

      await tester.tap(find.text('Create account')); // sheet's confirm, not the form's button
      await tester.pumpAndSettle();

      expect(
        _RecordingAuth.calls,
        ['John.Doe@students.livingstone.edu|John.Doe@gmail.com'],
      );
    });

    testWidgets('an invalid form never reaches the sheet', (tester) async {
      await _pumpRegister(tester);
      final fields = find.byType(TextFormField);
      // Personal address in the campus field — the domain check must fire first.
      await tester.enterText(fields.at(0), 'john.doe@gmail.com');
      await tester.enterText(fields.at(1), 'john.doe@gmail.com');
      await tester.enterText(fields.at(2), 'hunter2pass');
      await tester.enterText(fields.at(3), 'hunter2pass');
      await tester.pump();
      await _tapCreateAccount(tester);

      expect(find.text('Check your details'), findsNothing);
      expect(_RecordingAuth.calls, isEmpty);
    });
  });
}

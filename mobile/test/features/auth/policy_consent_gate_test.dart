import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/auth/screens/register_screen.dart';
import 'package:lc_connect/features/policies/data/policy_slugs.dart';
import 'package:lc_connect/features/policies/screens/policy_document_screen.dart';

/// No account may be created without the consent box ticked. The disabled button is the visible
/// half; `_submit`'s own guard is the half that covers the keyboard's Done key.
class _RecordingAuth extends AuthNotifier {
  static final calls = <String>[];

  @override
  Future<AuthUser?> build() async => null;

  @override
  Future<void> register(
    String email,
    String password, {
    required String contactEmail,
    required int policiesAcceptedVersion,
  }) async {
    calls.add('$email|v$policiesAcceptedVersion');
  }
}

class _DocsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    final slug = o.path.split('/').last;
    final body = File('../docs/policies/$slug.md').readAsStringSync();
    String j(String x) =>
        '"${x.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
    return ResponseBody.fromString(
      '{"slug":"$slug","title":"Doc","version":$kPolicyVersion,"body":${j(body)}}',
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://t/api/v1'))..httpClientAdapter = _DocsAdapter();
  final router = GoRouter(initialLocation: '/register', routes: [
    GoRoute(path: '/login', builder: (c, s) => const Scaffold(body: Text('login'))),
    GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
    GoRoute(
      path: '/policies/:slug',
      builder: (c, s) => PolicyDocumentScreen(slug: s.pathParameters['slug']!),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_RecordingAuth.new),
      apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
}

Future<void> _fillForm(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'jane@students.livingstone.edu');
  await tester.enterText(fields.at(1), 'jane@gmail.com');
  await tester.enterText(fields.at(2), 'hunter2pass');
  await tester.enterText(fields.at(3), 'hunter2pass');
  await tester.pump();
}

bool _consentTicked(WidgetTester tester) =>
    tester.widget<Checkbox>(find.byType(Checkbox)).value == true;

void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://t/api/v1\nENV=test'));

  setUp(_RecordingAuth.calls.clear);

  group('policy consent at signup', () {
    testWidgets('the consent sentence is present and starts unticked', (tester) async {
      await _pump(tester);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(_consentTicked(tester), isFalse);
      expect(
        find.textContaining('I agree to the', findRichText: true),
        findsOneWidget,
      );
      // One sentence carries both attestations — policies and address ownership.
      expect(
        find.textContaining('email addresses above are mine', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a complete form cannot be submitted while unticked', (tester) async {
      await _pump(tester);
      await _fillForm(tester);

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      // No confirm sheet, no signup — the button is inert, not merely refusing after the fact.
      expect(find.text('Check your details'), findsNothing);
      expect(_RecordingAuth.calls, isEmpty);
    });

    testWidgets('the keyboard Done key is not a way around the checkbox', (tester) async {
      // `onFieldSubmitted` on the confirm-password field calls _submit directly, bypassing the
      // button entirely. Without the guard inside _submit this would create an account.
      await _pump(tester);
      await _fillForm(tester);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Check your details'), findsNothing);
      expect(_RecordingAuth.calls, isEmpty);
    });

    testWidgets('ticking it lets the form through', (tester) async {
      await _pump(tester);
      await _fillForm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(_consentTicked(tester), isTrue);

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Check your details'), findsOneWidget);
    });

    testWidgets('the accepted version reaches register()', (tester) async {
      await _pump(tester);
      await _fillForm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account')); // the sheet's confirm
      await tester.pumpAndSettle();

      expect(_RecordingAuth.calls, ['jane@students.livingstone.edu|v$kPolicyVersion']);
    });

    testWidgets('tapping a policy link opens it WITHOUT ticking the box', (tester) async {
      // The reason the label is not tap-to-toggle: an outer gesture would compete with the link
      // recognizers, so reaching for "Privacy Policy" could silently record consent.
      await _pump(tester);
      expect(_consentTicked(tester), isFalse);

      await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.byType(PolicyDocumentScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(_consentTicked(tester), isFalse, reason: 'reading is not consenting');
    });

    testWidgets('reading a policy keeps the typed form intact', (tester) async {
      await _pump(tester);
      await _fillForm(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.tapOnText(find.textRange.ofSubstring('Terms of Service'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Pushed, not `go`-ed: the form survives the round trip, consent included.
      expect(find.text('jane@students.livingstone.edu'), findsOneWidget);
      expect(_consentTicked(tester), isTrue);
    });
  });
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/policies/data/policy_slugs.dart';
import 'package:lc_connect/features/policies/screens/policy_document_screen.dart';
import 'package:lc_connect/features/policies/screens/policy_gate_screen.dart';

/// Auth in a fixed state, so the router rule can be exercised directly.
class _FakeAuth extends AuthNotifier {
  static bool verified = true;
  static bool accepted = false;
  static bool profileCompleted = true;
  static bool acceptFails = false;
  static int acceptCalls = 0;
  static int logoutCalls = 0;

  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'u1',
        email: 'jane@students.livingstone.edu',
        role: 'student',
        isVerified: verified,
        policiesAccepted: accepted,
        profileCompleted: profileCompleted,
      );

  @override
  Future<void> acceptPolicies() async {
    acceptCalls++;
    if (acceptFails) throw DioException(requestOptions: RequestOptions(path: '/x'));
    accepted = true;
    state = AsyncData(state.value!.copyWith(policiesAccepted: true));
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AsyncData(null);
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

/// Mirrors the real router, `refreshListenable` included.
///
/// That listener is not incidental: without it the redirect never re-runs after acceptance, and
/// the user sits on the gate having just accepted. Leaving it out of the test would have skipped
/// the mechanism the whole gate depends on.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen<AsyncValue<AuthUser?>>(authNotifierProvider, (previous, next) => notifyListeners());
  }
}

final _testRouterProvider = Provider.family<GoRouter, String>((ref, initial) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
      refreshListenable: refresh,
      initialLocation: initial,
      routes: [
        GoRoute(path: '/login', builder: (c, s) => const Scaffold(body: Text('LOGIN'))),
        GoRoute(path: '/home', builder: (c, s) => const Scaffold(body: Text('HOME'))),
        GoRoute(path: '/onboarding', builder: (c, s) => const Scaffold(body: Text('ONBOARDING'))),
        GoRoute(path: '/verify-email', builder: (c, s) => const Scaffold(body: Text('VERIFY'))),
        GoRoute(path: '/accept-policies', builder: (c, s) => const PolicyGateScreen()),
        GoRoute(
          path: '/policies/:slug',
          builder: (c, s) => PolicyDocumentScreen(slug: s.pathParameters['slug']!),
        ),
      ],
      redirect: (context, state) {
        final loc = state.matchedLocation;
        if (loc.startsWith('/policies/')) return null;
        final isPolicyGate = loc == '/accept-policies';
        final isPublic = loc == '/login';
        final isVerify = loc == '/verify-email';
        final isOnboarding = loc == '/onboarding';
        final user = ref.read(authNotifierProvider).value;
        if (user == null) return isPublic ? null : '/login';
        if (!user.isVerified) {
          return isVerify || isPublic ? null : '/verify-email';
        }
        if (!user.policiesAccepted) {
          return isPolicyGate ? null : '/accept-policies';
        }
        if (isPolicyGate) {
          return user.profileCompleted ? '/home' : '/onboarding';
        }
        if (isPublic || isVerify) {
          return user.profileCompleted ? '/home' : '/onboarding';
        }
        if (!user.profileCompleted && !isOnboarding) return '/onboarding';
        if (user.profileCompleted && isOnboarding) return '/home';
        return null;
      },
    );
});

Future<void> _pump(WidgetTester tester, {String initial = '/home'}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://t/api/v1'))..httpClientAdapter = _DocsAdapter();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_FakeAuth.new),
      apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
    ],
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        routerConfig: ref.watch(_testRouterProvider(initial)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://t/api/v1\nENV=test'));

  setUp(() {
    _FakeAuth.verified = true;
    _FakeAuth.accepted = false;
    _FakeAuth.profileCompleted = true;
    _FakeAuth.acceptFails = false;
    _FakeAuth.acceptCalls = 0;
    _FakeAuth.logoutCalls = 0;
  });

  group('the router gate', () {
    testWidgets('an unaccepted user is pulled to the gate from anywhere', (tester) async {
      for (final start in ['/home', '/onboarding', '/login', '/verify-email']) {
        await _pump(tester, initial: start);
        expect(find.byType(PolicyGateScreen), findsOneWidget, reason: 'from $start');
      }
    });

    testWidgets('the gate comes before onboarding', (tester) async {
      // Policies first: onboarding is where a user creates content about themselves.
      _FakeAuth.profileCompleted = false;
      await _pump(tester, initial: '/home');
      expect(find.byType(PolicyGateScreen), findsOneWidget);
      expect(find.text('ONBOARDING'), findsNothing);
    });

    testWidgets('an accepted user never sees the gate', (tester) async {
      _FakeAuth.accepted = true;
      await _pump(tester, initial: '/home');
      expect(find.byType(PolicyGateScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('an unverified user never reaches the gate', (tester) async {
      // Email confirmation comes first. Starting from /home the async auth load transits through
      // "no user", which parks them on /login — a legitimate spot for an unverified account,
      // since it is their cancel path. Either way the gate is not it.
      _FakeAuth.verified = false;
      await _pump(tester, initial: '/home');
      expect(find.byType(PolicyGateScreen), findsNothing);
    });


    testWidgets('a signed-in reader is NOT bounced out of a policy document', (tester) async {
      // The regression this guards: `/policies/` was briefly inside `isPublicScreen`, so the
      // "verified user on a public screen → move forward" rule threw a reader out to /home
      // mid-document.
      _FakeAuth.accepted = true;
      await _pump(tester, initial: '/policies/${PolicySlug.terms}');
      expect(find.byType(PolicyDocumentScreen), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });
  });

  group('the gate screen', () {
    testWidgets('accept is inert until the box is ticked', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();
      expect(_FakeAuth.acceptCalls, 0);
      expect(find.byType(PolicyGateScreen), findsOneWidget);
    });

    testWidgets('ticking then accepting moves the user on', (tester) async {
      await _pump(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();

      expect(_FakeAuth.acceptCalls, 1);
      expect(find.byType(PolicyGateScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('accepting sends an incomplete profile to onboarding', (tester) async {
      _FakeAuth.profileCompleted = false;
      await _pump(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();
      expect(find.text('ONBOARDING'), findsOneWidget);
    });

    testWidgets('a failed accept keeps the user here and says so', (tester) async {
      _FakeAuth.acceptFails = true;
      await _pump(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();

      expect(find.byType(PolicyGateScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('sign out is the way out — this screen is never a trap', (tester) async {
      // The router lets a user leave here no other way. The onboarding lock taught us the cost.
      await _pump(tester);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(_FakeAuth.logoutCalls, 1);
    });

    testWidgets('the documents are readable from the gate, and it survives the trip',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final link = find.widgetWithText(ListTile, 'Privacy Policy');
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(PolicyDocumentScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(PolicyGateScreen), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('the summary names the three surprising things', (tester) async {
      await _pump(tester);
      expect(find.textContaining('visible to other signed-in members'), findsOneWidget);
      expect(find.textContaining('not end-to-end encrypted'), findsOneWidget);
      expect(find.textContaining('can cost'), findsOneWidget);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/core/router/app_router.dart';
import 'package:lc_connect/core/router/pending_deep_link.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/auth/screens/splash_screen.dart';

/// Beta report #11: "the login screen flashes during startup even for authenticated users."
///
/// The cause was structural, not cosmetic: `initialLocation` was `/login`, and the router read
/// `AsyncLoading` as "logged out", so a returning user was parked on an interactive login form
/// until `POST /auth/bootstrap` returned. On a cold free-tier backend that is up to a minute.
///
/// These tests pin the replacement contract — Launch → Splash → restore → App | Login — and the
/// deep-link queue that stops a notification tap being discarded during the same window.

/// Restore that never finishes, so the "still restoring" state can be observed.
class _RestoringForever extends AuthNotifier {
  @override
  Future<AuthUser?> build() => Completer<AuthUser?>().future;
}

/// Restore that resolves only when [completer] is completed.
class _RestoreOn extends AuthNotifier {
  _RestoreOn(this.completer);

  final Completer<AuthUser?> completer;

  @override
  Future<AuthUser?> build() async {
    try {
      return await completer.future;
    } finally {
      markSessionRestored();
    }
  }
}

/// Restore that failed because the backend was unreachable — the session is still valid.
class _Unreachable extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => throw const AuthRestoreUnreachable();
}

/// Restore that has already finished, with or without a user.
class _Restored extends AuthNotifier {
  _Restored(this.user);

  final AuthUser? user;

  @override
  Future<AuthUser?> build() async {
    markSessionRestored();
    return user;
  }
}

const _fullyOnboarded = AuthUser(
  id: 'u1',
  email: 'student@students.livingstone.edu',
  role: 'student',
  isVerified: true,
  policiesAccepted: true,
  profileCompleted: true,
);

/// Mounts the real router with a stubbed auth restore. Takes the notifier factory rather than an
/// override list because `Override` is not exported from `flutter_riverpod`, and every test here
/// varies only the restore behaviour.
/// Riverpod 3 retries a failed provider on an exponential backoff. In production that is exactly
/// what report #10 wants — a restore blocked by an unreachable backend keeps trying on its own.
/// In a widget test it means the tree never settles, so these containers opt out and assert the
/// state the retry would be recovering from.
Duration? _noRetry(int retryCount, Object error) => null;

Future<GoRouter> _pumpApp(WidgetTester tester, AuthNotifier Function() auth) async {
  final container = ProviderContainer(
    retry: _noRetry,
    overrides: [authNotifierProvider.overrideWith(auth)],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test'));

  group('startup never uses the login form as a loading screen', () {
    testWidgets('holds the splash while the session is still being restored', (tester) async {
      final router = await _pumpApp(tester, _RestoringForever.new);

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(router.state.matchedLocation, '/splash');
      // The regression: this used to be '/login', with a fully interactive form.
      expect(find.text('Sign in'), findsNothing);
    });

    // The remaining outcomes are asserted against `resolveRedirect` rather than a mounted app:
    // every destination past the splash (/home, /onboarding, /verify-email) needs an initialised
    // Supabase instance and the providers its screen touches, so mounting it tests the screen
    // rather than the gate. The gate is the part that can strand a user.
    test('a restored session resolves straight to the app — never through /login', () {
      expect(
        resolveRedirect(
          loc: '/splash',
          sessionRestored: true,
          isLoggedIn: true,
          isSuspended: false,
          isVerified: true,
          policiesAccepted: true,
          profileCompleted: true,
          awaitingEmailConfirmation: false,
        ),
        '/home',
      );
    });

    test('a restored session with an incomplete profile resolves to onboarding', () {
      expect(
        resolveRedirect(
          loc: '/splash',
          sessionRestored: true,
          isLoggedIn: true,
          isSuspended: false,
          isVerified: true,
          policiesAccepted: true,
          profileCompleted: false,
          awaitingEmailConfirmation: false,
        ),
        '/onboarding',
      );
    });
  });

  /// The gate that decides, for every auth state, whether a location is allowed. Extracted from
  /// the router precisely so these cases can be enumerated.
  group('resolveRedirect', () {
    String? at(
      String loc, {
      bool sessionRestored = true,
      bool isLoggedIn = false,
      bool isSuspended = false,
      bool isVerified = false,
      bool policiesAccepted = false,
      bool profileCompleted = false,
      bool awaitingEmailConfirmation = false,
    }) =>
        resolveRedirect(
          loc: loc,
          sessionRestored: sessionRestored,
          isLoggedIn: isLoggedIn,
          isSuspended: isSuspended,
          isVerified: isVerified,
          policiesAccepted: policiesAccepted,
          profileCompleted: profileCompleted,
          awaitingEmailConfirmation: awaitingEmailConfirmation,
        );

    // Signed-in, verified, consented, onboarded.
    String? ready(String loc) => at(
          loc,
          isLoggedIn: true,
          isVerified: true,
          policiesAccepted: true,
          profileCompleted: true,
        );

    group('while the session is still being restored', () {
      test('every location is held at the splash', () {
        for (final loc in ['/home', '/login', '/messages', '/notifications', '/attendance/scan']) {
          expect(at(loc, sessionRestored: false), '/splash', reason: loc);
        }
      });

      test('the splash itself stays put', () {
        expect(at('/splash', sessionRestored: false), isNull);
      });

      test('a policy document is still readable — it has no account prerequisite', () {
        expect(at('/policies/terms-of-service', sessionRestored: false), isNull);
      });
    });

    group('once restored', () {
      test('nobody is left sitting on the splash', () {
        expect(at('/splash'), '/login');
        expect(ready('/splash'), '/home');
        expect(at('/splash', isLoggedIn: true), '/verify-email');
        expect(at('/splash', isLoggedIn: true, isVerified: true), '/accept-policies');
      });

      test('a suspended account is confined to /suspended', () {
        expect(at('/home', isLoggedIn: true, isSuspended: true), '/suspended');
        expect(at('/suspended', isLoggedIn: true, isSuspended: true), isNull);
        // Suspension outranks the restore gate's successor rules, including the splash.
        expect(at('/splash', isLoggedIn: true, isSuspended: true), '/suspended');
      });

      test('a non-suspended user cannot sit on /suspended', () {
        expect(ready('/suspended'), '/login');
      });

      test('an anonymous user is confined to the public screens', () {
        for (final loc in ['/login', '/register', '/forgot-password', '/reset-password']) {
          expect(at(loc), isNull, reason: loc);
        }
        expect(at('/home'), '/login');
        expect(at('/messages'), '/login');
      });

      test('the gates apply in order: verify, then policies, then onboarding', () {
        expect(at('/home', isLoggedIn: true), '/verify-email');
        expect(at('/home', isLoggedIn: true, isVerified: true), '/accept-policies');
        expect(
          at('/home', isLoggedIn: true, isVerified: true, policiesAccepted: true),
          '/onboarding',
        );
        expect(ready('/home'), isNull);
      });

      test('a stale policy acceptance cannot be skipped by landing on a public screen', () {
        // Regression the ordering was written for: the policy gate comes before the
        // "verified user on a public screen → move forward" rule.
        expect(at('/login', isLoggedIn: true, isVerified: true), '/accept-policies');
        expect(at('/verify-email', isLoggedIn: true, isVerified: true), '/accept-policies');
      });

      test('a signed-in reader is not thrown out of a policy document', () {
        expect(ready('/policies/privacy-policy'), isNull);
        expect(at('/policies/privacy-policy', isLoggedIn: true, isVerified: true), isNull);
      });

      test('a finished onboarding does not leave the user on it', () {
        expect(ready('/onboarding'), '/home');
        expect(
          at('/onboarding', isLoggedIn: true, isVerified: true, policiesAccepted: true),
          isNull,
        );
      });

      test('awaiting email confirmation keeps only verify and login reachable', () {
        expect(at('/home', awaitingEmailConfirmation: true), '/verify-email');
        expect(at('/verify-email', awaitingEmailConfirmation: true), isNull);
        expect(at('/login', awaitingEmailConfirmation: true), isNull);
      });
    });
  });

  /// Beta report #10: "users should not repeatedly authenticate while a valid session can
  /// securely be restored". The cause was not a token lifetime — `AuthNotifier.build` called
  /// `_auth.signOut()` on *any* non-suspension bootstrap failure, so a cold-start timeout at
  /// launch threw away a perfectly good refresh token.
  group('an unreachable backend does not end the session', () {
    testWidgets('stays on the splash instead of falling through to login', (tester) async {
      final router = await _pumpApp(tester, _Unreachable.new);
      await tester.pump();

      expect(router.state.matchedLocation, '/splash');
      // The regression: an unreachable server used to sign the user out, landing them here.
      expect(router.state.matchedLocation, isNot('/login'));
    });

    testWidgets('offers the retry immediately, without waiting out the stall timer',
        (tester) async {
      await _pumpApp(tester, _Unreachable.new);
      await tester.pump();

      // No timer advance: the failure is already definitive, so making the user wait 20s to be
      // told what the app already knows would be pointless.
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('session is still saved'), findsOneWidget);
    });

    test('the restore is not marked finished, so the router keeps holding', () {
      final container = ProviderContainer(
        retry: _noRetry,
        overrides: [authNotifierProvider.overrideWith(_Unreachable.new)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(authNotifierProvider, (_, _) {});
      addTearDown(sub.close);

      expect(
        container.read(authNotifierProvider.notifier).sessionRestored,
        isFalse,
        reason: 'an unreachable backend is not an answer about the session',
      );
    });

    test('a definitive "no session" does mark the restore finished', () {
      final container = ProviderContainer(
        retry: _noRetry,
        overrides: [authNotifierProvider.overrideWith(() => _Restored(null))],
      );
      addTearDown(container.dispose);
      final sub = container.listen(authNotifierProvider, (_, _) {});
      addTearDown(sub.close);

      expect(container.read(authNotifierProvider.notifier).sessionRestored, isTrue);
    });
  });

  group('splash screen states', () {
    testWidgets('reports progress immediately and admits a slow wait', (tester) async {
      await _pumpApp(tester, _RestoringForever.new);

      expect(find.text('Signing you in…'), findsOneWidget);

      await tester.pump(SplashScreen.slowAfter);
      expect(find.text('Still connecting…'), findsOneWidget);
    });

    testWidgets('offers a retry once the wait is unreasonable, and says the session is safe',
        (tester) async {
      await _pumpApp(tester, _RestoringForever.new);

      await tester.pump(SplashScreen.stalledAfter);
      expect(find.text('Try again'), findsOneWidget);
      // Reassurance matters here: the old behaviour made users think they had been signed out.
      expect(find.textContaining('session is still saved'), findsOneWidget);
    });

    testWidgets('does not offer a retry before it is plausibly stalled', (tester) async {
      await _pumpApp(tester, _RestoringForever.new);

      await tester.pump(SplashScreen.slowAfter);
      expect(find.text('Try again'), findsNothing,
          reason: 'retrying early cancels a request that is usually about to succeed');
    });
  });

  group('pending deep link', () {
    test('queues while the app cannot navigate, and drains once it can', () async {
      final completer = Completer<AuthUser?>();
      final container = ProviderContainer(retry: _noRetry, overrides: [
        authNotifierProvider.overrideWith(() => _RestoreOn(completer)),
      ]);
      addTearDown(container.dispose);
      container.read(deepLinkDrainProvider);

      var opened = 0;
      container.read(pendingDeepLinkProvider.notifier).enqueue((_) => opened++);

      // Restore in flight: pushing now would be redirected to the splash and lost.
      await Future<void>.delayed(Duration.zero);
      expect(opened, 0);
      expect(container.read(pendingDeepLinkProvider), isNotNull, reason: 'still queued');

      completer.complete(_fullyOnboarded);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(opened, 1);
      expect(container.read(pendingDeepLinkProvider), isNull, reason: 'consumed exactly once');
    });

    test('does not drain for an account still behind a gate', () async {
      final container = ProviderContainer(retry: _noRetry, overrides: [
        authNotifierProvider.overrideWith(
          () => _Restored(const AuthUser(
            id: 'u4',
            email: 'a@students.livingstone.edu',
            role: 'student',
            isVerified: true,
            // Policies not accepted — the router would bounce any push to /accept-policies.
          )),
        ),
      ]);
      addTearDown(container.dispose);
      container.read(deepLinkDrainProvider);

      var opened = 0;
      container.read(pendingDeepLinkProvider.notifier).enqueue((_) => opened++);
      await Future<void>.delayed(Duration.zero);

      expect(opened, 0);
      expect(container.read(pendingDeepLinkProvider), isNotNull,
          reason: 'held, not discarded — the tap is honoured after the gate clears');
    });

    test('the most recent tap wins when several queue up', () async {
      final container = ProviderContainer(retry: _noRetry, overrides: [
        authNotifierProvider.overrideWith(_RestoringForever.new),
      ]);
      addTearDown(container.dispose);
      container.read(deepLinkDrainProvider);

      final opened = <String>[];
      final notifier = container.read(pendingDeepLinkProvider.notifier);
      notifier.enqueue((_) => opened.add('first'));
      notifier.enqueue((_) => opened.add('second'));

      final open = notifier.take();
      expect(open, isNotNull);
      open!(container.read(routerProvider));

      // Single slot: whichever notification the user tapped last is the one they want.
      expect(opened, ['second']);
      expect(container.read(pendingDeepLinkProvider), isNull, reason: 'take() clears the slot');
    });
  });
}

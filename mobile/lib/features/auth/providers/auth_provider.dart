import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../data/duplicate_signup.dart';
import 'suspension_provider.dart';
import '../../messages/data/chat_draft_store.dart';
import '../../messages/data/chat_message_cache.dart';

class AuthUser {
  final String id;
  final String email;
  final String role;
  final bool isVerified;
  /// Whether the stored acceptance matches the backend's current policy version. A boolean, not
  /// the version number — the app never needs to know the numbering, only whether it is current.
  final bool policiesAccepted;
  final bool profileCompleted;

  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.isVerified = false,
    this.policiesAccepted = false,
    this.profileCompleted = false,
  });

  factory AuthUser.fromBootstrap(Map<String, dynamic> json) => AuthUser(
        id: json['id'].toString(),
        email: json['email'] as String,
        role: json['role'] as String? ?? 'student',
        isVerified: json['is_verified'] as bool? ?? false,
        // Absent means an older server, or a response we cannot read — treat as not accepted, so
        // the failure mode is "asked again" rather than "silently let through".
        policiesAccepted: json['policies_accepted'] as bool? ?? false,
        profileCompleted: json['profile_completed'] as bool? ?? false,
      );

  AuthUser copyWith({bool? isVerified, bool? policiesAccepted, bool? profileCompleted}) =>
      AuthUser(
        id: id,
        email: email,
        role: role,
        isVerified: isVerified ?? this.isVerified,
        policiesAccepted: policiesAccepted ?? this.policiesAccepted,
        profileCompleted: profileCompleted ?? this.profileCompleted,
      );
}

/// Thrown when the stored session could not be restored because the backend was unreachable.
///
/// Distinct from a *rejected* session: the credentials are intact and worth keeping, so the app
/// must offer a retry rather than sign the user out. The splash screen renders this as
/// "we can't reach LC Connect right now" with the session preserved.
class AuthRestoreUnreachable implements Exception {
  const AuthRestoreUnreachable();

  @override
  String toString() => 'AuthRestoreUnreachable: the backend could not be reached';
}

/// Set when bootstrap returns 403 `account_suspended` — session stays alive so the user can appeal.
class SuspendedSession {
  final String email;

  const SuspendedSession({required this.email});
}

class SuspendedSessionNotifier extends Notifier<SuspendedSession?> {
  @override
  SuspendedSession? build() => null;

  void set(SuspendedSession? value) => state = value;
}

final suspendedSessionProvider =
    NotifierProvider<SuspendedSessionNotifier, SuspendedSession?>(SuspendedSessionNotifier.new);

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthUser?>(
  AuthNotifier.new,
);

class AuthNotifier extends AsyncNotifier<AuthUser?> {
  GoTrueClient get _auth => Supabase.instance.client.auth;
  String? _pendingEmail;
  String? _pendingContactEmail;
  bool _sessionRestored = false;

  String? get pendingEmail => _pendingEmail;
  String? get pendingContactEmail => _pendingContactEmail;

  /// Whether the **initial** session restore has finished — with a session, without one, or
  /// having failed. Until then the app genuinely does not know who the user is.
  ///
  /// This is deliberately *not* `state.isLoading`. [login] also sets `AsyncLoading`, and treating
  /// that as "restoring" would throw the user onto the splash screen the moment they tapped
  /// Sign in. Only the one-time [build] flips this flag.
  bool get sessionRestored => _sessionRestored;

  /// Marks the initial restore as finished, whatever its outcome.
  ///
  /// `@protected` and separate from [build] because a subclass that overrides [build] — every test
  /// double does — would otherwise never flip the flag, and the router would hold the splash
  /// screen forever. Any override of [build] must call this on every return path.
  @protected
  void markSessionRestored() => _sessionRestored = true;

  @override
  Future<AuthUser?> build() async {
    final sub = _auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        ref.read(suspendedSessionProvider.notifier).set(null);
        state = const AsyncData(null);
      }
    });
    ref.onDispose(sub.cancel);

    // [markSessionRestored] is called on every path that reaches a *definitive* answer — signed
    // in, not signed in, or suspended — because that is what lets the router leave the splash.
    // It is deliberately NOT called when the backend was unreachable: there is no answer yet, so
    // the app stays on the splash (which offers a retry) instead of falling through to the login
    // form, which is what made a network blip look like a sign-out.
    if (_auth.currentSession == null) {
      markSessionRestored();
      return null;
    }
    try {
      final user = await _bootstrap();
      markSessionRestored();
      return user;
    } on DioException catch (e) {
      if (isAccountSuspendedError(e)) {
        _markSuspended();
        markSessionRestored();
        return null;
      }
      // Beta report #10 — "users have to authenticate repeatedly". This branch used to be an
      // unconditional `await _auth.signOut()`, which destroyed a perfectly valid session
      // (refresh token and all) whenever the *backend* call failed. A cold-start timeout or a
      // moment of flaky campus Wi-Fi at launch signed the user out and made them log in again.
      // Nothing was wrong with their credentials.
      //
      // The two cases are now distinguished: a session the server *rejected* is dead and must
      // go, but a server we could not *reach* says nothing about the session — so keep it, and
      // surface a retry.
      //
      // Throwing (rather than returning null) is also what gets the retry for free: Riverpod
      // retries a failed provider on an exponential backoff, so the restore keeps trying by
      // itself while the splash shows its manual "Try again" alongside.
      if (_isUnreachable(e)) {
        throw const AuthRestoreUnreachable();
      }
      await _auth.signOut();
      markSessionRestored();
      return null;
    }
  }

  /// Whether a failure means "could not reach the server" rather than "the server said no".
  ///
  /// Mirrors the classification `_UnreachableInterceptor` already applies in `api_client.dart`,
  /// plus 5xx: a server error is the backend's problem, never evidence about this session.
  static bool _isUnreachable(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      default:
        final status = error.response?.statusCode;
        return status != null && status >= 500;
    }
  }

  void _markSuspended() {
    final email = _auth.currentSession?.user.email ?? '';
    ref.read(suspendedSessionProvider.notifier).set(SuspendedSession(email: email));
  }

  Future<AuthUser> _bootstrap() async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.post('/auth/bootstrap');
    ref.read(suspendedSessionProvider.notifier).set(null);
    return AuthUser.fromBootstrap(response.data as Map<String, dynamic>);
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await _auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final session = result.session;
      if (session == null) {
        throw AuthException('No session returned. Confirm your email first.');
      }
      try {
        return await _bootstrap();
      } on DioException catch (e) {
        if (isAccountSuspendedError(e)) {
          _markSuspended();
          return null;
        }
        // Sign-in succeeded but the account never bootstrapped, so there is no usable session —
        // drop it. Leaving it alive showed "can't reach LC Connect" while the user was in fact
        // signed in to Supabase, and a relaunch then failed and signed them out anyway, making
        // one cold start look like two separate login failures.
        await _auth.signOut();
        rethrow;
      }
    });
  }

  Future<void> register(
    String email,
    String password, {
    required String contactEmail,
    required int policiesAcceptedVersion,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final normalized = email.trim().toLowerCase();
      final normalizedContact = contactEmail.trim().toLowerCase();
      final result = await _auth.signUp(
        email: normalized,
        password: password,
        // The accepted version travels in signup metadata because there is nowhere else for it to
        // go yet: no session and no LC Connect user row exist until the email code is confirmed.
        // The backend reads it from the JWT claims on first bootstrap and writes it to the user
        // row — clamped to its own current version, since metadata is client-writable.
        data: {
          'contact_email': normalizedContact,
          'policies_accepted_version': policiesAcceptedVersion,
        },
      );
      // Must come before the session check: a duplicate signup also has no session, so without
      // this it looks identical to "awaiting confirmation" and strands the user on the verify
      // screen waiting for a code Supabase never sends. See [isDuplicateSignup].
      if (isDuplicateSignup(result)) {
        throw const AuthException(
          'An account already exists for that email.',
          code: 'user_already_exists',
        );
      }
      final session = result.session;
      if (session == null) {
        _pendingEmail = normalized;
        _pendingContactEmail = normalizedContact;
        return null;
      }
      _pendingEmail = null;
      _pendingContactEmail = null;
      return _bootstrap();
    });
  }

  /// True when signup succeeded but Supabase has not issued a session yet.
  bool get awaitingEmailConfirmation =>
      _pendingEmail != null && state.asData?.value == null;

  Future<void> verifyEmailOtp({required String email, required String token}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final normalized = email.trim().toLowerCase();
      final result = await _auth.verifyOTP(
        type: OtpType.signup,
        email: normalized,
        token: token.trim(),
      );
      final session = result.session;
      if (session == null) {
        throw AuthException('Verification succeeded but no session was created.');
      }
      _pendingEmail = null;
      _pendingContactEmail = null;
      return _bootstrap();
    });
  }

  Future<void> resendSignupOtp(String email) async {
    await _auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  Future<void> resetPasswordWithOtp({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    final result = await _auth.verifyOTP(
      type: OtpType.recovery,
      email: email.trim().toLowerCase(),
      token: token.trim(),
    );
    final session = result.session;
    if (session == null) {
      throw AuthException('Invalid or expired reset code.');
    }
    await _auth.updateUser(UserAttributes(password: newPassword));
    await _auth.signOut();
  }

  /// Records acceptance for the signed-in user, then refreshes so the router can move on.
  ///
  /// Covers the two cases signup metadata cannot: an account created before the gate shipped, and
  /// a re-prompt after the backend's policy version is raised. Rethrows so the gate screen can
  /// show the failure rather than appearing to succeed and staying put.
  Future<void> acceptPolicies() async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.post('/auth/accept-policies');
    state = AsyncData(AuthUser.fromBootstrap(response.data as Map<String, dynamic>));
  }

  Future<void> refreshVerification() async {
    await _refreshFromServer();
  }

  /// Re-reads the account so `profileCompleted` is current and the router can move on.
  ///
  /// Rethrows on failure. It used to swallow every exception, which produced the worst bug in the
  /// flow: onboarding saved the profile successfully, this call failed (a cold start is the norm
  /// on first run), and the app never learned the profile was complete — so the router kept the
  /// student on /onboarding with no error, no retry, and a Finish button that silently re-saved
  /// the same data forever. Callers must surface the failure.
  Future<void> refreshProfile() async {
    await _refreshFromServer();
  }

  /// Leaves `state` untouched on failure — a failed refresh must not destroy a working session —
  /// but lets the caller see that it failed.
  Future<void> _refreshFromServer() async {
    if (state.asData?.value == null) return;
    final user = await _bootstrap();
    state = AsyncData(user);
  }

  /// After an admin reactivates the account, retry bootstrap without signing out.
  Future<void> retryAfterSuspension() async {
    ref.read(suspendedSessionProvider.notifier).set(null);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        return await _bootstrap();
      } on DioException catch (e) {
        if (isAccountSuspendedError(e)) {
          _markSuspended();
          return null;
        }
        rethrow;
      }
    });
  }

  Future<void> logout() async {
    _pendingEmail = null;
    _pendingContactEmail = null;
    ref.read(suspendedSessionProvider.notifier).set(null);
    await _clearLocalChatData();
    await _auth.signOut();
    state = const AsyncLoading();
    state = const AsyncData(null);
  }

  /// Drops locally stored conversation content on the way out.
  ///
  /// Both stores are on-device only and neither was being cleared: signing out left cached
  /// message bodies and unsent drafts on disk for the next person to sign in. That matters on
  /// shared campus devices, and an unsent draft is the most private thing in the feature — it was
  /// never shown to anyone.
  ///
  /// Awaited before `signOut` so the deletion cannot be cut short by the teardown that follows,
  /// and each store swallows its own failures so a cleanup problem can never trap a user in a
  /// session they are trying to leave.
  Future<void> _clearLocalChatData() async {
    await ref.read(chatDraftStoreProvider).clearAll();
    await ref.read(chatMessageCacheProvider).clearAll();
  }

  /// Leave the verify-email gate and return to login/register.
  Future<void> cancelEmailConfirmation() async {
    await logout();
  }
}

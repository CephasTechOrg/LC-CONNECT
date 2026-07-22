import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/storage/secure_storage.dart';

class AuthUser {
  final String id;
  final String email;
  final String role;
  final bool isVerified;
  final bool profileCompleted;

  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.isVerified = false,
    this.profileCompleted = false,
  });

  factory AuthUser.fromBootstrap(Map<String, dynamic> json) => AuthUser(
        id: json['id'].toString(),
        email: json['email'] as String,
        role: json['role'] as String? ?? 'student',
        isVerified: json['is_verified'] as bool? ?? false,
        profileCompleted: json['profile_completed'] as bool? ?? false,
      );

  AuthUser copyWith({bool? isVerified, bool? profileCompleted}) => AuthUser(
        id: id,
        email: email,
        role: role,
        isVerified: isVerified ?? this.isVerified,
        profileCompleted: profileCompleted ?? this.profileCompleted,
      );
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthUser?>(
  AuthNotifier.new,
);

class AuthNotifier extends AsyncNotifier<AuthUser?> {
  GoTrueClient get _auth => Supabase.instance.client.auth;
  String? _pendingEmail;

  String? get pendingEmail => _pendingEmail;

  @override
  Future<AuthUser?> build() async {
    // React to Supabase session changes: keep the stored token fresh after a
    // background refresh, and flip to signed-out (→ router redirects to login)
    // when the session is revoked or the refresh token expires.
    final sub = _auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.tokenRefreshed:
          final refreshed = data.session;
          if (refreshed != null) {
            ref.read(secureStorageProvider).saveToken(refreshed.accessToken);
          }
        case AuthChangeEvent.signedOut:
          ref.read(secureStorageProvider).deleteToken();
          state = const AsyncData(null);
        default:
          break;
      }
    });
    ref.onDispose(sub.cancel);

    final session = _auth.currentSession;
    if (session == null) {
      await ref.read(secureStorageProvider).deleteToken();
      return null;
    }
    await ref.read(secureStorageProvider).saveToken(session.accessToken);
    try {
      return await _bootstrap();
    } on DioException {
      await _auth.signOut();
      await ref.read(secureStorageProvider).deleteToken();
      return null;
    }
  }

  Future<AuthUser> _bootstrap() async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.post('/auth/bootstrap');
    return AuthUser.fromBootstrap(response.data as Map<String, dynamic>);
  }

  Future<void> _persistSession(Session session) async {
    await ref.read(secureStorageProvider).saveToken(session.accessToken);
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
      await _persistSession(session);
      return _bootstrap();
    });
  }

  Future<void> register(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final normalized = email.trim().toLowerCase();
      final result = await _auth.signUp(
        email: normalized,
        password: password,
      );
      final session = result.session;
      if (session == null) {
        _pendingEmail = normalized;
        return null;
      }
      _pendingEmail = null;
      await _persistSession(session);
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
      await _persistSession(session);
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

  Future<void> refreshVerification() async {
    final current = state.asData?.value;
    if (current == null) return;
    try {
      final user = await _bootstrap();
      state = AsyncData(user);
    } catch (_) {}
  }

  Future<void> refreshProfile() async {
    final current = state.asData?.value;
    if (current == null) return;
    try {
      final user = await _bootstrap();
      state = AsyncData(user);
    } catch (_) {}
  }

  Future<void> logout() async {
    _pendingEmail = null;
    await _auth.signOut();
    await ref.read(secureStorageProvider).deleteToken();
    state = const AsyncData(null);
  }
}

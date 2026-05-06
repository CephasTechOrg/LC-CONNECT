import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/storage/secure_storage.dart';

class AuthUser {
  final String id;
  final String email;
  final String role;
  final bool profileCompleted;

  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.profileCompleted = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json, {bool profileCompleted = false}) =>
      AuthUser(
        id: json['id'].toString(),
        email: json['email'],
        role: json['role'] ?? 'student',
        profileCompleted: profileCompleted,
      );

  AuthUser copyWith({bool? profileCompleted}) => AuthUser(
        id: id,
        email: email,
        role: role,
        profileCompleted: profileCompleted ?? this.profileCompleted,
      );
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthUser?>(
  AuthNotifier.new,
);

class AuthNotifier extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() async {
    final storage = ref.watch(secureStorageProvider);
    final token = await storage.getToken();
    if (token == null) return null;

    try {
      final client = ref.watch(apiClientProvider);
      final meResponse = await client.dio.get('/auth/me');
      final profileCompleted = await _fetchProfileCompleted(client);
      return AuthUser.fromJson(meResponse.data, profileCompleted: profileCompleted);
    } on DioException {
      await storage.deleteToken();
      return null;
    }
  }

  Future<bool> _fetchProfileCompleted(ApiClient client) async {
    try {
      final response = await client.dio.get('/profiles/me');
      return (response.data['profile_completed'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(apiClientProvider);
      final storage = ref.read(secureStorageProvider);
      final response = await client.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final token = response.data['access_token'] as String;
      await storage.saveToken(token);
      final meResponse = await client.dio.get('/auth/me');
      final profileCompleted = await _fetchProfileCompleted(client);
      return AuthUser.fromJson(meResponse.data, profileCompleted: profileCompleted);
    });
  }

  Future<void> register(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(apiClientProvider);
      final storage = ref.read(secureStorageProvider);
      final registerResponse = await client.dio.post('/auth/register', data: {
        'email': email,
        'password': password,
      });
      final token = registerResponse.data['access_token'] as String;
      await storage.saveToken(token);
      final meResponse = await client.dio.get('/auth/me');
      final profileCompleted = await _fetchProfileCompleted(client);
      return AuthUser.fromJson(meResponse.data, profileCompleted: profileCompleted);
    });
  }

  // Called after onboarding submit — refreshes profileCompleted without full re-auth.
  Future<void> refreshProfile() async {
    final current = state.asData?.value;
    if (current == null) return;
    try {
      final client = ref.read(apiClientProvider);
      final profileCompleted = await _fetchProfileCompleted(client);
      state = AsyncData(current.copyWith(profileCompleted: profileCompleted));
    } catch (_) {}
  }

  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.deleteToken();
    state = const AsyncData(null);
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/storage/secure_storage.dart';

// Represents the authenticated user's basic info
class AuthUser {
  final String id;
  final String email;
  final String role;

  const AuthUser({required this.id, required this.email, required this.role});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'].toString(),
        email: json['email'],
        role: json['role'] ?? 'student',
      );
}

// Loads current user from /auth/me — null means unauthenticated
final authStateProvider = FutureProvider<AuthUser?>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  final token = await storage.getToken();
  if (token == null) return null;

  try {
    final client = ref.watch(apiClientProvider);
    final response = await client.dio.get('/auth/me');
    return AuthUser.fromJson(response.data);
  } on DioException {
    await storage.deleteToken();
    return null;
  }
});

// Auth notifier for login/register/logout actions
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
      final response = await client.dio.get('/auth/me');
      return AuthUser.fromJson(response.data);
    } on DioException {
      await storage.deleteToken();
      return null;
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
      return AuthUser.fromJson(meResponse.data);
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
      return AuthUser.fromJson(meResponse.data);
    });
  }

  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.deleteToken();
    state = const AsyncData(null);
  }
}

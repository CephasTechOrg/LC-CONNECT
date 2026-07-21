import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../storage/secure_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(storage);
});

class ApiClient {
  final SecureStorage _storage;
  late final Dio _dio;

  ApiClient(this._storage) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        contentType: 'application/json',
      ),
    );
    _dio.interceptors.add(_AuthInterceptor(_storage));
  }

  Dio get dio => _dio;
}

class _AuthInterceptor extends Interceptor {
  final SecureStorage _storage;
  _AuthInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Prefer the live Supabase access token; fall back to stored token.
    final sessionToken = Supabase.instance.client.auth.currentSession?.accessToken;
    final token = sessionToken ?? await _storage.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

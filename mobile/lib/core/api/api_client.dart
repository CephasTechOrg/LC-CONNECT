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
    _dio.interceptors.add(_AuthInterceptor(_storage, _dio));
  }

  Dio get dio => _dio;
}

/// Attaches the current Supabase access token to every request and recovers from
/// a 401 by refreshing the session once and replaying the request. If the refresh
/// token itself is dead, it signs out so the router redirects to login.
class _AuthInterceptor extends Interceptor {
  static const _retriedFlag = '__auth_retried__';

  final SecureStorage _storage;
  final Dio _dio;
  Future<bool>? _refreshing;

  _AuthInterceptor(this._storage, this._dio);

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Prefer the live Supabase access token; fall back to stored token.
    final token = _auth.currentSession?.accessToken ?? await _storage.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;

    // Only try to recover a 401 once, and only when we actually have a session.
    if (!is401 || alreadyRetried || _auth.currentSession == null) {
      return handler.next(err);
    }

    final refreshed = await _refreshSession();
    if (!refreshed) {
      // Refresh token expired/revoked — force sign-out; the auth listener + router
      // will send the user back to login.
      await _auth.signOut();
      await _storage.deleteToken();
      return handler.next(err);
    }

    try {
      final options = err.requestOptions..extra[_retriedFlag] = true;
      // Replaying through _dio re-runs onRequest, which attaches the fresh token.
      final response = await _dio.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }

  /// Shares a single in-flight refresh across concurrent 401s so we never fire
  /// multiple refreshes at once (which would rotate refresh tokens against itself).
  Future<bool> _refreshSession() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    try {
      final session = (await _auth.refreshSession()).session;
      if (session == null) return false;
      await _storage.saveToken(session.accessToken);
      return true;
    } catch (_) {
      return false;
    }
  }
}

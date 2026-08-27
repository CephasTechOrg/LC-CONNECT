import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import 'health_provider.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    onUnreachable: () {
      // Tip the offline banner immediately when REST can't reach the host.
      ref.read(backendStatusProvider.notifier).reportUnreachable();
    },
  );
});

class ApiClient {
  late final Dio _dio;

  /// [dio] is an injection seam for tests: pass a pre-configured Dio (e.g. with a
  /// stub adapter) to bypass the network + auth interceptor. Production passes none.
  ApiClient({Dio? dio, VoidCallback? onUnreachable}) {
    if (dio != null) {
      _dio = dio;
      return;
    }
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: AppConstants.connectTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        contentType: 'application/json',
      ),
    );
    _dio.interceptors.add(_AuthInterceptor(_dio));
    if (onUnreachable != null) {
      _dio.interceptors.add(_UnreachableInterceptor(onUnreachable));
    }
  }

  Dio get dio => _dio;
}

/// Marks the app offline when a request fails for network reasons (not HTTP 4xx/5xx).
class _UnreachableInterceptor extends Interceptor {
  _UnreachableInterceptor(this._onUnreachable);
  final VoidCallback _onUnreachable;

  static bool _isUnreachable(DioExceptionType type) =>
      type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.connectionError;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_isUnreachable(err.type)) _onUnreachable();
    handler.next(err);
  }
}

/// Attaches the current Supabase access token to every request and recovers from
/// a 401 by refreshing the session once and replaying the request. If the refresh
/// token itself is dead, it signs out so the router redirects to login.
class _AuthInterceptor extends Interceptor {
  static const _retriedFlag = '__auth_retried__';

  final Dio _dio;
  Future<bool>? _refreshing;

  _AuthInterceptor(this._dio);

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // The Supabase session is the single source of truth for the bearer token; it is restored
    // from the keystore at startup, so there is no second copy to fall back to.
    final token = _auth.currentSession?.accessToken;
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
      return true;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:async';

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
    _dio.interceptors.add(DedupeGetInterceptor());
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

/// Collapses identical **concurrent** GETs into a single request.
///
/// Public only so tests can install it on their own Dio. `ApiClient`'s `dio:` parameter is an
/// injection seam that deliberately skips the interceptor stack, so a test passing a stub adapter
/// through it would exercise a bare Dio and pass for the wrong reason.
///
/// Several independent providers legitimately ask for the same thing at the same moment — the
/// Groups tab mounts pending-invites, your-groups and discover together; a screen and a widget
/// inside it both want the profile. Each was a separate HTTP call for the same bytes.
///
/// This is **not** a response cache. Nothing is stored and nothing goes stale: the entry is
/// dropped the instant the first caller finishes, so only calls that genuinely overlap in time are
/// merged. That keeps it safe for the reads that must never be cached — attendance state, unread
/// counts — which still gain from not being fetched twice in the same millisecond.
///
/// The single-flight shape mirrors `_AuthInterceptor._refreshSession`, which already does this for
/// token refresh so concurrent 401s cannot rotate the refresh token against itself.
@visibleForTesting
class DedupeGetInterceptor extends Interceptor {
  /// In-flight leaders by request identity. A follower awaits the leader's future.
  final _leaders = <String, Completer<Response<dynamic>>>{};

  /// Set on the leader's options so [onResponse]/[onError] can find its entry again. Carrying it
  /// on the request rather than recomputing the key keeps the two sides impossible to disagree.
  static const _leaderKeyField = '__dedupe_leader_key__';

  /// Method + path + query. Headers are excluded deliberately: the only one that varies is the
  /// bearer token, and two requests in flight together always carry the same one.
  static String _identity(RequestOptions options) {
    final query = options.queryParameters.entries.map((e) => '${e.key}=${e.value}').toList()
      ..sort();
    return '${options.method.toUpperCase()} ${options.path}?${query.join("&")}';
  }

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // GETs only. A repeated POST/PATCH/DELETE is a second *intent*, never a duplicate read, and
    // merging those would silently drop a user's action.
    if (options.method.toUpperCase() != 'GET') return handler.next(options);

    final key = _identity(options);
    final leader = _leaders[key];
    if (leader != null) {
      try {
        final response = await leader.future;
        // Rebound to this caller's options, so anything downstream reading
        // `response.requestOptions` still sees its own request.
        return handler.resolve(
          Response<dynamic>(
            data: response.data,
            headers: response.headers,
            statusCode: response.statusCode,
            statusMessage: response.statusMessage,
            requestOptions: options,
          ),
        );
      } on DioException catch (error) {
        // The leader failed, so every follower fails with it. Re-issuing the request here instead
        // would re-enter the interceptor chain from inside an awaited `onRequest`, which
        // deadlocks — and it is not worth the cleverness: these calls were made in the same
        // moment over the same connection, so a follower's independent attempt would almost
        // certainly fail the same way. Callers already handle errors, and the retry paths that
        // matter (pull-to-refresh, Riverpod's provider retry, the send ladder) sit above this.
        return handler.reject(error);
      } catch (error, stackTrace) {
        // Non-Dio failure: still must not leave the caller hanging on a dead leader.
        return handler.reject(
          DioException(requestOptions: options, error: error, stackTrace: stackTrace),
        );
      }
    }

    final completer = Completer<Response<dynamic>>();
    // Registers an error handler up front. Without it, a leader that fails with no follower
    // waiting surfaces as an unhandled async error even though the caller handled it properly.
    unawaited(completer.future.then((_) {}, onError: (Object _) {}));
    _leaders[key] = completer;
    options.extra[_leaderKeyField] = key;
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _settle(response.requestOptions, (completer) => completer.complete(response));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _settle(err.requestOptions, (completer) => completer.completeError(err));
    handler.next(err);
  }

  void _settle(RequestOptions options, void Function(Completer<Response<dynamic>>) finish) {
    // Prefer the key carried on the request, but fall back to recomputing it.
    //
    // The fallback is not belt-and-braces — it prevents a hang. Anything that replaces the
    // `RequestOptions` on the way out (a DioException constructed with fresh options, a
    // transformer, a future interceptor) loses `extra`, and without a fallback the leader's entry
    // would never be cleared and every follower would wait on it forever. An orphaned entry costs
    // one duplicate request; an unsettled one costs the user a screen that never loads.
    final key = (options.extra[_leaderKeyField] as String?) ?? _identity(options);
    final completer = _leaders.remove(key);
    if (completer != null && !completer.isCompleted) finish(completer);
  }
}

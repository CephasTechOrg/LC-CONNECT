import 'dart:io';

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../api/api_client.dart';
import '../router/app_router.dart';
import '../../features/messages/providers/messages_provider.dart';
import '../../features/messages/utils/message_navigation.dart';

/// Guarded FCM wrapper. If Firebase isn't configured yet (no google-services files),
/// `initialize()` no-ops and push stays disabled — the app runs normally. Once the
/// Firebase setup (see docs/features/notifications/firebase_setup.md) is in place, push activates.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  bool _available = false;
  String? _token;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _messageOpenedSub;
  bool _listenersAttached = false;

  bool get available => _available;

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _available = true;
    } catch (e) {
      _available = false; // Firebase not configured yet — push disabled, app unaffected.
      if (kDebugMode) debugPrint('Push disabled (Firebase not configured): $e');
    }
  }

    Future<void> registerForUser(
    Dio dio, {
    required void Function(String conversationId) onOpenConversation,
    required void Function(String postId) onOpenCampusPost,
    required VoidCallback onOpenNotifications,
    required VoidCallback onOpenAttendanceScanner,
  }) async {
    if (!_available) return;
    if (_listenersAttached) return;
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        _token = token;
        await _register(dio, token);
      }
      _tokenRefreshSub = messaging.onTokenRefresh.listen((refreshed) {
        _token = refreshed;
        _register(dio, refreshed);
      });
      void open(RemoteMessage m) =>
          _open(m, onOpenConversation, onOpenCampusPost, onOpenNotifications, onOpenAttendanceScanner);
      _messageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(open);
      final initial = await messaging.getInitialMessage();
      if (initial != null) open(initial);
      _listenersAttached = true;
    } catch (e) {
      if (kDebugMode) debugPrint('Push registration failed: $e');
    }
  }

  void _open(
    RemoteMessage message,
    void Function(String) onOpenConversation,
    void Function(String) onOpenCampusPost,
    VoidCallback onOpenNotifications,
    VoidCallback onOpenAttendanceScanner,
  ) {
    final data = message.data;
    final type = data['type'];
    if (type == 'honors_attendance_open') {
      onOpenAttendanceScanner();
      return;
    }
    if (type == 'campus_post') {
      final postId = data['post_id'];
      if (postId is String && postId.isNotEmpty) {
        onOpenCampusPost(postId);
        return;
      }
    }
    if (type == 'notification') {
      // Connection/group-invite pushes — the notifications screen has the full detail + action.
      onOpenNotifications();
      return;
    }
    final conversationId = data['conversation_id'];
    if (conversationId is String && conversationId.isNotEmpty) {
      onOpenConversation(conversationId);
    }
  }

  Future<void> _register(Dio dio, String token) async {
    try {
      await dio.post('/devices', data: {'token': token, 'platform': _platform});
    } catch (_) {
      // best-effort; retried on next token refresh / app launch
    }
  }

  /// Called on logout: unregister the token so this device stops receiving pushes.
  Future<void> clear(Dio dio) async {
    if (!_available) return;
    await _tokenRefreshSub?.cancel();
    await _messageOpenedSub?.cancel();
    _tokenRefreshSub = null;
    _messageOpenedSub = null;
    _listenersAttached = false;
    final token = _token;
    if (token != null) {
      try {
        await dio.delete('/devices/$token');
      } catch (_) {}
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
  }

  String get _platform => Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
          ? 'android'
          : 'web';
}

/// Registers/clears the FCM token in step with auth. Watch once at the app root.
final notificationRegistrarProvider = Provider<void>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  ref.listen<AsyncValue<AuthUser?>>(authNotifierProvider, (_, next) {
    if (next.asData?.value != null) {
      NotificationService.instance.registerForUser(
        dio,
        onOpenConversation: (conversationId) {
          openMessageConversation(
            router: ref.read(routerProvider),
            conversationId: conversationId,
            threads: ref.read(threadsNotifierProvider).asData?.value,
          );
        },
        onOpenCampusPost: (postId) {
          ref.read(routerProvider).push('/home/posts/$postId');
        },
        onOpenNotifications: () {
          ref.read(routerProvider).push('/notifications');
        },
        onOpenAttendanceScanner: () {
          ref.read(routerProvider).push('/attendance/scan');
        },
      );
    } else {
      NotificationService.instance.clear(dio);
    }
  }, fireImmediately: true);
});

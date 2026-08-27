import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';

enum BackendStatus { checking, online, offline }

/// Live reachability of the API (`GET /health`). Polls while the app is open and
/// re-checks on resume so the offline banner stays accurate without a device-only
/// connectivity plugin (server down ≠ "no Wi‑Fi").
final backendStatusProvider =
    NotifierProvider<BackendStatusNotifier, BackendStatus>(
  BackendStatusNotifier.new,
);

class BackendStatusNotifier extends Notifier<BackendStatus> {
  static const _onlineInterval = Duration(seconds: 45);
  static const _offlineInterval = Duration(seconds: 8);
  static const _probeTimeout = Duration(seconds: 5);

  Timer? _timer;
  _LifecycleObserver? _lifecycle;
  int _probeGeneration = 0;
  Dio? _probe;

  @override
  BackendStatus build() {
    _probe = Dio(
      BaseOptions(
        // /health lives on the host root, not under /api/v1.
        baseUrl: AppConstants.apiBaseUrl.replaceAll(RegExp(r'/api/v1/?$'), ''),
        connectTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
        sendTimeout: _probeTimeout,
      ),
    );

    _lifecycle = _LifecycleObserver(checkNow);
    WidgetsBinding.instance.addObserver(_lifecycle!);

    ref.onDispose(() {
      _timer?.cancel();
      _probe?.close(force: true);
      final life = _lifecycle;
      if (life != null) WidgetsBinding.instance.removeObserver(life);
    });

    // First probe after build so we don't block provider construction.
    Future.microtask(checkNow);
    return BackendStatus.checking;
  }

  /// Immediate reachability check (resume, manual retry, first paint).
  Future<void> checkNow() async {
    final gen = ++_probeGeneration;
    final dio = _probe;
    if (dio == null) return;

    BackendStatus next;
    try {
      await dio.get<void>('/health');
      next = BackendStatus.online;
    } catch (_) {
      next = BackendStatus.offline;
    }

    if (gen != _probeGeneration) return; // superseded by a newer check
    if (!ref.mounted) return;
    state = next;
    _scheduleNext();
  }

  /// Tip the UI to offline immediately when a REST call fails on the network
  /// (banner appears before the next poll). A successful health check still
  /// clears it.
  void reportUnreachable() {
    if (state == BackendStatus.offline) return;
    state = BackendStatus.offline;
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    final delay =
        state == BackendStatus.offline ? _offlineInterval : _onlineInterval;
    _timer = Timer(delay, checkNow);
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

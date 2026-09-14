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

  /// Long enough to survive a cold start. The API is hosted on a plan that spins down when
  /// idle, so the first request after a quiet period can take far longer than a warm one. A 5s
  /// probe reported "offline" during exactly the window a user was trying to send in, while
  /// the real request (30s timeout) was still in flight and about to succeed.
  static const _probeTimeout = Duration(seconds: 15);

  /// Consecutive failures before showing the offline banner. One failure is more often a cold
  /// start or a blip than an outage, and a banner that cries wolf teaches users to ignore it.
  static const _failuresBeforeOffline = 2;

  Timer? _timer;
  _LifecycleObserver? _lifecycle;
  int _probeGeneration = 0;
  int _consecutiveFailures = 0;
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

    var reachable = true;
    try {
      await dio.get<void>('/health');
    } catch (_) {
      reachable = false;
    }

    if (gen != _probeGeneration) return; // superseded by a newer check
    if (!ref.mounted) return;
    _consecutiveFailures = reachable ? 0 : _consecutiveFailures + 1;
    // Hold the current state through a single failure: a lone miss is usually the server
    // waking up, and flipping to "offline" mid-send is worse than a moment of staleness. On a
    // first probe that misses, this leaves the state at `checking` rather than accusing the
    // server of being down before we have evidence.
    if (reachable) {
      state = BackendStatus.online;
    } else if (_consecutiveFailures >= _failuresBeforeOffline) {
      state = BackendStatus.offline;
    }
    _scheduleNext();
  }

  /// Tip the UI to offline immediately when a REST call fails on the network
  /// (banner appears before the next poll). A successful health check still
  /// clears it.
  void reportUnreachable() {
    if (state == BackendStatus.offline) return;
    // A real request already failed on the network, which is stronger evidence than a probe
    // miss — trust it immediately rather than waiting for a second failure.
    _consecutiveFailures = _failuresBeforeOffline;
    state = BackendStatus.offline;
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    final unhealthy = state == BackendStatus.offline || _consecutiveFailures > 0;
    final delay = unhealthy ? _offlineInterval : _onlineInterval;
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

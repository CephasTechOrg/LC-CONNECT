import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/campus_post.dart';

/// Client-side "new opportunities" badge for the Campus Hub quick action.
///
/// Deliberately separate from Latest Updates / announcement unread:
/// - Latest Updates = announcements only (server unread + WS ping)
/// - Opportunities = this cursor — posts published after the student last opened Opportunities
///
/// No server unread table yet; a local last-seen timestamp is enough for the hub affordance.
final opportunityNewCountProvider =
    NotifierProvider<OpportunityNewCountNotifier, int>(OpportunityNewCountNotifier.new);

class OpportunityNewCountNotifier extends Notifier<int> {
  static const _lastSeenKey = 'campus_hub.opportunities_last_seen';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  StreamSubscription<void>? _reconnectSub;
  _OpportunityResumeObserver? _resumeObserver;

  @override
  int build() {
    ref.watch(authNotifierProvider.select((a) => a.asData?.value?.id));
    ref.keepAlive();

    try {
      // Re-seed after WS reconnect / app resume so a publish while backgrounded still badges.
      final realtime = ref.watch(realtimeClientProvider);
      _reconnectSub = realtime.reconnected.listen((_) => refresh());
    } catch (_) {
      // Realtime unavailable in widget tests — badge still works via refresh()/markSeen().
    }

    _resumeObserver = _OpportunityResumeObserver(refresh);
    WidgetsBinding.instance.addObserver(_resumeObserver!);
    ref.onDispose(() {
      _reconnectSub?.cancel();
      if (_resumeObserver != null) {
        WidgetsBinding.instance.removeObserver(_resumeObserver!);
      }
    });

    Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    final userId = ref.read(authNotifierProvider).asData?.value?.id;
    if (userId == null) {
      state = 0;
      return;
    }
    try {
      final raw = await _storage.read(key: _lastSeenKey);
      if (raw == null) {
        // First visit: baseline to now so historical opportunities don't all light up.
        await _storage.write(
          key: _lastSeenKey,
          value: DateTime.now().toUtc().toIso8601String(),
        );
        state = 0;
        return;
      }
      final lastSeen = DateTime.parse(raw).toUtc();
      final client = ref.read(apiClientProvider);
      final response = await client.dio.get(
        '/campus-hub/posts',
        queryParameters: {'kind': 'opportunity'},
      );
      final posts = (response.data as List)
          .map((j) => CampusPostSummary.fromJson(j as Map<String, dynamic>))
          .toList();
      state = posts.where((p) => p.publishAt.toUtc().isAfter(lastSeen)).length;
    } catch (_) {
      /* keep current; next resume/refresh retries */
    }
  }

  /// Opening the Opportunities list clears the badge (same mental model as "I've seen these").
  Future<void> markSeen() async {
    await _storage.write(
      key: _lastSeenKey,
      value: DateTime.now().toUtc().toIso8601String(),
    );
    state = 0;
  }
}

class _OpportunityResumeObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _OpportunityResumeObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

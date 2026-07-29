import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/campus_post.dart';

class CampusPostsQuery {
  final String? kind;
  final String? priority;
  final String? category;

  const CampusPostsQuery({this.kind, this.priority, this.category});

  @override
  bool operator ==(Object other) =>
      other is CampusPostsQuery &&
      other.kind == kind &&
      other.priority == priority &&
      other.category == category;

  @override
  int get hashCode => Object.hash(kind, priority, category);
}

final campusHubOverviewProvider = FutureProvider<CampusHubOverview>((ref) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/campus-hub/overview');
  return CampusHubOverview.fromJson(response.data as Map<String, dynamic>);
});

final campusPostsProvider =
    FutureProvider.family<List<CampusPostSummary>, CampusPostsQuery>((ref, query) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get(
    '/campus-hub/posts',
    queryParameters: {
      if (query.kind != null) 'kind': query.kind,
      if (query.priority != null) 'priority': query.priority,
      if (query.category != null) 'category': query.category,
    },
  );
  return (response.data as List)
      .map((json) => CampusPostSummary.fromJson(json as Map<String, dynamic>))
      .toList();
});

// ── Live "new announcements" counter ──────────────────────────────
/// Mirrors the notification bell counter, but for announcements: it ticks up in real time on the
/// WS `announcement` ping (filtered to the viewer's audience) and clears when they open the
/// announcements page. Session-live (starts at 0 each launch) — there's no per-user read state to
/// seed from, so it counts what arrives while the app is running.
final announcementCountProvider =
    NotifierProvider<AnnouncementCountNotifier, int>(AnnouncementCountNotifier.new);

class AnnouncementCountNotifier extends Notifier<int> {
  StreamSubscription<InboundEvent>? _sub;

  @override
  int build() {
    final role = ref.watch(authNotifierProvider.select((a) => a.asData?.value?.role)) ?? 'student';
    final RealtimeClient client;
    try {
      client = ref.watch(realtimeClientProvider);
    } catch (_) {
      return 0; // realtime/env unavailable (e.g. widget tests) — no badge
    }
    _sub = client.events.listen((event) {
      if (event is AnnouncementEvent && _appliesTo(event.audience, role)) {
        state = state + 1;
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return 0;
  }

  bool _appliesTo(String audience, String role) {
    switch (audience) {
      case 'students':
        return role == 'student';
      case 'staff':
        return role != 'student';
      default: // 'all'
        return true;
    }
  }

  /// Clear the badge — called when the announcements list opens (they've seen them all).
  void markSeen() => state = 0;

  /// Reading one announcement removes one from the count (never below zero).
  void decrement() => state = state > 0 ? state - 1 : 0;
}

// ── Announcements feed (paginated / infinite scroll) ──────────────
const _announcementsPageSize = 15;

class AnnouncementsState {
  final List<CampusPostSummary> items;
  final bool hasMore;
  final bool loadingMore;

  const AnnouncementsState({
    required this.items,
    required this.hasMore,
    required this.loadingMore,
  });

  AnnouncementsState copyWith({List<CampusPostSummary>? items, bool? hasMore, bool? loadingMore}) =>
      AnnouncementsState(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Announcements only (opportunities have their own page), loaded a page at a time — scroll to
/// pull in older ones. Auto-disposes so re-opening the page shows a fresh first page.
final announcementsProvider =
    AsyncNotifierProvider.autoDispose<AnnouncementsNotifier, AnnouncementsState>(
        AnnouncementsNotifier.new);

class AnnouncementsNotifier extends AsyncNotifier<AnnouncementsState> {
  @override
  Future<AnnouncementsState> build() async {
    ref.watch(authNotifierProvider);
    final first = await _fetch(0);
    return AnnouncementsState(
      items: first,
      hasMore: first.length >= _announcementsPageSize,
      loadingMore: false,
    );
  }

  Future<List<CampusPostSummary>> _fetch(int offset) async {
    final response = await ref.read(apiClientProvider).dio.get(
      '/campus-hub/posts',
      queryParameters: {
        'kind': 'announcement',
        'limit': _announcementsPageSize,
        'offset': offset,
      },
    );
    return (response.data as List)
        .map((json) => CampusPostSummary.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Append the next page. No-op while a page is in flight or once we've reached the end.
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _fetch(current.items.length);
      state = AsyncData(AnnouncementsState(
        items: [...current.items, ...next],
        hasMore: next.length >= _announcementsPageSize,
        loadingMore: false,
      ));
    } catch (_) {
      // Keep what we have; a scroll retry or pull-to-refresh recovers.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }
}

final campusPostProvider = FutureProvider.family<CampusPost, String>((ref, postId) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/campus-hub/posts/$postId');
  return CampusPost.fromJson(response.data as Map<String, dynamic>);
});

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a cached provider keeps its value after the last listener goes away.
///
/// Long enough to cover ordinary back-and-forth navigation — open a group, read it, go back,
/// open another — which is what "revisiting causes everything to reload" actually describes.
/// Short enough that a list is never more than a few minutes stale, and mutations invalidate
/// explicitly anyway, so this is only the ceiling on *passive* staleness.
const defaultCacheWindow = Duration(minutes: 5);

/// Keeps a provider's value for [window] after its last listener is removed.
///
/// `autoDispose` providers throw their value away the instant the screen unmounts, so every visit
/// is a cold fetch behind a skeleton. With `ShellRoute` switching tabs by *replacing* the stack
/// (`context.go`), that fires on every tab change: opening the Groups tab used to cost three
/// requests and three skeletons, every single time.
///
/// Plain `keepAlive()` is the other extreme — the value is held for the life of the app and never
/// refreshes. This is the middle: cached for a window, then released so the next read is fresh.
///
/// ```dart
/// final myGroupsProvider = FutureProvider.autoDispose<List<GroupSummary>>((ref) {
///   cacheFor(ref);
///   return ref.watch(groupsRepositoryProvider).myGroups();
/// });
/// ```
///
/// Only meaningful on an `autoDispose` provider — a non-disposing one is already kept forever.
///
/// On a `family`, each argument caches separately, so the memory held is bounded by
/// (distinct arguments used in the window) rather than by anything unbounded. That is the point
/// for search-backed families: typing "stu" then deleting back to "st" reuses the earlier result
/// instead of re-querying.
void cacheFor(Ref ref, [Duration window = defaultCacheWindow]) {
  final link = ref.keepAlive();
  final timer = Timer(window, link.close);
  // Without this the timer outlives a provider disposed for another reason (auth change,
  // explicit invalidate) and calls `close` on a dead link.
  ref.onDispose(timer.cancel);
}

extension AsyncValueCache<T> on AsyncValue<T> {
  /// Renders from a known value whenever there is one — **including a stale value currently being
  /// refreshed** — and shows [loading] only on a genuine first load.
  ///
  /// `AsyncValue.when` shows `loading` during *any* reload, so a cached screen still collapsed to
  /// a skeleton the moment it revalidated. That defeats the point of caching: the data was right
  /// there. This is the stale-while-revalidate half of the fix — cached content stays on screen
  /// while fresh content is fetched behind it.
  ///
  /// Precedence is deliberately the same as `eligibilityFrom`: a known answer wins, then an error,
  /// then "still waiting".
  R cached<R>({
    required R Function(T value) data,
    required R Function() loading,
    required R Function(Object error, StackTrace stackTrace) error,
  }) {
    final known = value;
    if (known != null) return data(known);
    if (hasError) return error(this.error!, stackTrace ?? StackTrace.empty);
    return loading();
  }

  /// Whether a refresh is happening behind content that is already on screen.
  ///
  /// For a subtle indicator — a thin progress line, a dimmed header — rather than replacing the
  /// content the user is reading.
  bool get isRevalidating => isLoading && value != null;
}

/// "Online" / "Last seen …" as a chat header shows it — pure, so the wording is testable.
library;

import '../../../shared/util/app_date_format.dart';

/// [online] wins; otherwise the last-seen time in the most natural form for how long ago it was.
/// Null when there is nothing to say (hidden, or never seen).
String? presenceLabel({required bool online, DateTime? lastSeenAt, DateTime? now}) {
  if (online) return 'Online';
  if (lastSeenAt == null) return null;
  final seen = lastSeenAt.toLocal();
  final today = now ?? DateTime.now();
  final day = DateTime(seen.year, seen.month, seen.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  final daysAgo = todayDay.difference(day).inDays;
  final time = AppDateFormat.time(seen);
  if (daysAgo <= 0) return 'Last seen today at $time';
  if (daysAgo == 1) return 'Last seen yesterday at $time';
  if (daysAgo < 7) return 'Last seen ${AppDateFormat.fullWeekday(seen)} at $time';
  return 'Last seen ${AppDateFormat.dayMonth(seen)}';
}

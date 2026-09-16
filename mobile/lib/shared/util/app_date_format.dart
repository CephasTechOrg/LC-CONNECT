import 'package:intl/intl.dart';

/// The single place any timestamp becomes text.
///
/// **The invariant: `.toLocal()` is applied here, exactly once, and nowhere else.**
///
/// Why this module exists. The API serialises timestamps with an explicit offset
/// (`2026-09-16T22:00:00+00:00`), so `DateTime.parse` returns a DateTime with `isUtc == true`.
/// `DateFormat.format()` renders a DateTime's *own* wall-clock fields and ignores `isUtc` — so
/// formatting a parsed timestamp directly prints **UTC time labelled as local**. That is how a
/// 6:00 PM activity came to display as 10:00 PM (EDT is UTC−4): five call sites formatted
/// `activity.startTime` without converting first, while the dashboard preview did convert, so the
/// same activity showed two different times in one app.
///
/// Patching those call sites would not have prevented the next one. The rule instead is:
/// **`DateFormat` is only ever constructed inside this file.** Every caller passes an instant and
/// gets a string, and cannot get the conversion wrong because it has no conversion to do.
///
/// Callers may pass a UTC-flagged or a local DateTime interchangeably — the same instant always
/// formats identically, which is what `app_date_format_test.dart` pins down.
class AppDateFormat {
  const AppDateFormat._();

  // Cached: DateFormat parses its pattern on construction, and these render in list builders.
  static final DateFormat _compactDate = DateFormat('EEE, MMM d'); // Tue, Sep 16
  static final DateFormat _fullDate = DateFormat('EEEE, MMMM d, y'); // Tuesday, September 16, 2026
  static final DateFormat _dayMonth = DateFormat('MMM d'); // Sep 16
  static final DateFormat _weekday = DateFormat('EEE'); // Tue
  static final DateFormat _time = DateFormat('h:mm a'); // 6:00 PM

  /// Compact date for lists and cards — `Tue, Sep 16`.
  static String date(DateTime at) => _compactDate.format(at.toLocal());

  /// Long date for detail screens — `Tuesday, September 16, 2026`.
  static String fullDate(DateTime at) => _fullDate.format(at.toLocal());

  /// Month and day only — `Sep 16`.
  static String dayMonth(DateTime at) => _dayMonth.format(at.toLocal());

  /// Time of day — `6:00 PM`.
  static String time(DateTime at) => _time.format(at.toLocal());

  /// Time range — `6:00 PM – 8:00 PM`, or just the start when [end] is null.
  ///
  /// Uses an en dash, matching the two private copies of this helper it replaces.
  static String timeRange(DateTime start, DateTime? end) {
    final from = time(start);
    if (end == null) return from;
    return '$from – ${time(end)}';
  }

  /// Date and time together — `Tue, Sep 16 · 6:00 PM`.
  static String dateTime(DateTime at) => '${date(at)} · ${time(at)}';

  /// Coarse elapsed time — `Just now`, `5m ago`, `3h ago`, `2d ago`, `4w ago`, then a date.
  ///
  /// Beyond four weeks a relative label stops being informative ("9w ago"), so it falls back to
  /// [dayMonth]. Pass [now] to make a test deterministic; it defaults to the current instant.
  ///
  /// A future timestamp (clock skew between device and server) reads as `Just now` rather than a
  /// negative age.
  static String relative(DateTime at, {DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).difference(at);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return 'Just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
    if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
    if (elapsed.inDays < 28) return '${(elapsed.inDays / 7).floor()}w ago';
    return dayMonth(at);
  }

  /// Conversation/notification list stamp — time today, weekday this week, else `Sep 16`.
  ///
  /// Deliberately not [relative]: a message list reads better with a clock time for today than
  /// with "14m ago", which is the convention every mature messaging app follows.
  static String listStamp(DateTime at, {DateTime? now}) {
    final localAt = at.toLocal();
    final localNow = (now ?? DateTime.now()).toLocal();
    if (_isSameDay(localAt, localNow)) return _time.format(localAt);
    final elapsed = localNow.difference(localAt);
    if (!elapsed.isNegative && elapsed.inDays < 7) return _weekday.format(localAt);
    return _dayMonth.format(localAt);
  }

  /// Calendar-day bucket for message date separators.
  ///
  /// Returns a **local** midnight, so grouping matches the day the reader actually saw the
  /// message rather than the UTC day.
  static DateTime dayBucket(DateTime at) {
    final local = at.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Day label for a message date separator — `Today`, `Yesterday`, or a date.
  static String daySeparator(DateTime at, {DateTime? now}) {
    final day = dayBucket(at);
    final today = dayBucket(now ?? DateTime.now());
    final delta = today.difference(day).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (delta < 7 && delta > 0) return _weekday.format(day);
    return _dayMonth.format(day);
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

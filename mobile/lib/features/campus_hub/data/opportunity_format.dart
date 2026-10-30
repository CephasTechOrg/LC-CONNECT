/// How an opportunity's type, posting date and deadline read — one set of rules for the list card
/// and the detail screen, which used to word the same deadline two ways ("Closes Oct 28" and
/// "Deadline: Oct 28, 2026") and count days left by rounding down.
library;

import '../../../shared/util/app_date_format.dart';

/// Singular, for one card: "Internship · Campus · Posted Oct 3". The plural labels are for filters.
String opportunityTypeLabel(String? category) => switch (category) {
      'internship' => 'Internship',
      'job' => 'Job',
      'volunteer' => 'Volunteer role',
      'leadership' => 'Leadership role',
      _ => 'Opportunity',
    };

String postedLabel(DateTime publishAt, {DateTime? now}) =>
    'Posted ${AppDateFormat.dayMonthMaybeYear(publishAt, now: now)}';

typedef DeadlineLabel = ({String text, bool urgent});

/// Days counted by calendar date, not by elapsed hours: something closing at 11:59 PM the day
/// after tomorrow is "2 days left" all day today, not "1 day left" by the afternoon.
DeadlineLabel deadlineLabel(DateTime? closesAt, String? category, {DateTime? now}) {
  if (closesAt == null) {
    final rolling = category == 'internship' || category == 'job';
    return (text: rolling ? 'Open until filled' : 'Ongoing', urgent: false);
  }
  final today = now ?? DateTime.now();
  final close = closesAt.toLocal();
  final days = DateTime(close.year, close.month, close.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  if (days <= 0) return (text: 'Closes today', urgent: true);
  if (days == 1) return (text: 'Closes tomorrow', urgent: true);
  if (days <= 3) return (text: '$days days left', urgent: true);
  return (text: 'Closes ${AppDateFormat.dayMonthMaybeYear(close, now: today)}', urgent: false);
}

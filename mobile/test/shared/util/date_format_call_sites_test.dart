import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guard for beta report #9.
///
/// The bug was not that five call sites were wrong — it was that **any** call site could be wrong.
/// `DateFormat(...).format(x)` silently prints UTC wall-clock time when `x` came from
/// `DateTime.parse` of a server timestamp, and nothing in the codebase inspected `isUtc`. Five
/// sites had the defect; seventeen others happened to remember `.toLocal()`.
///
/// So the invariant worth enforcing is *where* formatting may happen:
/// **`DateFormat` is constructed only inside `app_date_format.dart`.**
///
/// [migrationBacklog] lists files that still construct their own `DateFormat` and are believed
/// correct (they call `.toLocal()` themselves). It exists so the debt is visible and can only
/// shrink — a **new** file cannot be added without editing this test, which is the point. Removing
/// entries as those sites migrate to `AppDateFormat` is Phase 4 tidy-up.
///
/// It was seeded from the tree rather than guessed, and the second test keeps it honest: an entry
/// that no longer needs migrating fails, so it cannot rot into a stale allowlist that quietly
/// permits nothing.
void main() {
  /// Known-correct sites pending migration. Do not add to this list: route new formatting through
  /// `AppDateFormat` instead.
  const migrationBacklog = <String>{
    'lib/features/activities/widgets/activity_form_fields.dart',
    'lib/features/attendance/widgets/attendance_result.dart',
    'lib/features/campus_hub/screens/campus_post_detail_screen.dart',
    'lib/features/campus_hub/screens/compose_campus_post_screen.dart',
    'lib/features/campus_hub/widgets/campus_home_previews.dart',
    'lib/features/campus_hub/widgets/campus_post_card.dart',
    'lib/features/campus_hub/widgets/campus_updates_panel.dart',
    'lib/features/campus_hub/widgets/opportunity_card.dart',
    'lib/features/messages/screens/messages_screen.dart',
    'lib/features/messages/widgets/chat_bubble.dart',
    'lib/features/messages/widgets/chat_message_list.dart',
  };

  const owner = 'lib/shared/util/app_date_format.dart';

  test('DateFormat is only constructed in app_date_format.dart or a backlogged file', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path;
      if (path == owner || migrationBacklog.contains(path)) continue;
      if (RegExp(r'\bDateFormat\s*[(.]').hasMatch(entity.readAsStringSync())) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These files construct a DateFormat directly. Use AppDateFormat, which applies '
          '.toLocal() internally — formatting a parsed server timestamp without it prints UTC '
          'labelled as local (a 6:00 PM activity showed as 10:00 PM). If a site genuinely needs '
          'its own pattern, add it to AppDateFormat rather than to the backlog.',
    );
  });

  test('the migration backlog only names files that still exist and still need migrating', () {
    // Stops the backlog rotting into a list of stale paths that silently permits nothing.
    for (final path in migrationBacklog) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path no longer exists — drop it from the backlog');
      expect(
        RegExp(r'\bDateFormat\s*[(.]').hasMatch(file.readAsStringSync()),
        isTrue,
        reason: '$path no longer constructs a DateFormat — drop it from the backlog',
      );
    }
  });

  test('the files fixed for report #9 are no longer in the backlog', () {
    // The five sites named in the review, plus the connections one.
    const fixed = <String>[
      'lib/features/activities/screens/activities_screen.dart',
      'lib/features/activities/screens/activity_detail_screen.dart',
      'lib/features/activities/widgets/activities_featured_card.dart',
      'lib/features/activities/widgets/activities_compact_card.dart',
      'lib/features/connections/screens/connections_screen.dart',
    ];
    for (final path in fixed) {
      expect(migrationBacklog, isNot(contains(path)));
      expect(
        RegExp(r'\bDateFormat\s*[(.]').hasMatch(File(path).readAsStringSync()),
        isFalse,
        reason: '$path regressed to formatting dates itself',
      );
    }
  });
}

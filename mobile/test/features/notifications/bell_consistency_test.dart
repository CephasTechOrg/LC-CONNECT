import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Report #20 (4.5) — "the notification bell is mounted in three places".
///
/// The count was the less interesting half. The problem was that one of those mountings was a
/// *different implementation*: the Campus Hub header had a private `_HomeBell`, a bare
/// `IconButton` with a hand-rolled badge, no tooltip and no semantics label. So on the app's
/// landing screen a screen reader announced nothing about unread notifications, while the same
/// control on Discovery and Activities announced "Notifications, 3 unread".
///
/// A source test rather than a widget test, because the property is "there is only one of these
/// in the codebase" — which no amount of pumping a widget can show.
void main() {
  final lib = Directory('lib');

  List<File> dartFiles() => lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('exactly one widget opens the notification centre', () {
    // The property that matters: one control owns "tap → notifications". A second hand-rolled
    // one is how an accessible bell and an inaccessible bell came to coexist.
    //
    // `AppBellIcon` is *not* an exception to this — it is the shared badge icon that the button
    // below renders, and it has no tap of its own.
    final owners = <String>[];
    for (final file in dartFiles()) {
      // The deep-link handler legitimately navigates there from a push notification.
      if (file.path.endsWith('notification_service.dart')) continue;
      if (file.readAsStringSync().contains("push('/notifications')")) {
        owners.add(file.path.split('/').last);
      }
    }

    expect(owners, ['notifications_bell_button.dart'],
        reason: 'only the shared bell should open the notification centre; found: $owners');
  });

  test('every bell mounting uses the shared widget', () {
    // Each of these is a top-level tab, so a bell on each is reachability rather than clutter —
    // what matters is that all three are the *same* control.
    final mountings = dartFiles()
        .where((f) => f.readAsStringSync().contains('NotificationsBellButton('))
        .map((f) => f.path.split('/').last)
        .toSet();

    expect(mountings, contains('campus_home_header.dart'));
    expect(mountings, contains('discovery_screen.dart'));
    expect(mountings, contains('activities_header.dart'));
  });

  test('the shared bell announces the unread count', () {
    // The whole point of unifying on it. Without a label the bell is an unlabelled icon and the
    // count is invisible to anyone not looking at it.
    final source =
        File('lib/features/notifications/widgets/notifications_bell_button.dart').readAsStringSync();

    expect(source, contains('unread'));
    expect(source, contains('semanticsLabel'));
  });
}

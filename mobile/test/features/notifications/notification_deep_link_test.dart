import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/notifications/data/notification_models.dart';

/// Report #15 — "tapping a notification only ever opens the inbox".
///
/// Group and connection rows always deep-linked; the attendance rows were the gap, and they were
/// the gap in the worst way: the row opened the scanner with **no session id**, so the scanner
/// re-derived which session was meant from "whichever is currently active". The moment one
/// session closed and another opened, a tap on the older notification silently opened the wrong
/// one — or said "Attendance is closed" with no indication of which session that referred to.
void main() {
  AppNotification notification({
    required String type,
    String? groupId,
    String? targetType,
    String? targetId,
  }) =>
      AppNotification(
        id: 'n1',
        type: type,
        read: false,
        createdAt: DateTime.utc(2026, 9, 18, 14),
        groupId: groupId,
        targetType: targetType,
        targetId: targetId,
      );

  group('attendance rows carry their session', () {
    test('the route includes the session id', () {
      final n = notification(
        type: 'honors_attendance_open',
        targetType: 'attendance_session',
        targetId: 'sess-42',
      );

      expect(n.route, '/attendance/scan?session=sess-42');
    });

    test('a row written before the target existed still opens the scanner', () {
      // The migration adds the column with no backfill, so rows already in the database have no
      // target. They must still work — degraded to the old behaviour, not broken.
      final n = notification(type: 'honors_attendance_open');

      expect(n.route, '/attendance/scan');
    });
  });

  group('other types are unchanged', () {
    test('a group row opens its group', () {
      expect(notification(type: 'group_invite', groupId: 'g1').route, '/groups/g1');
    });

    test('a connection row opens the connections screen', () {
      expect(notification(type: 'connection_accepted').route, '/connections');
    });

    test('scholar verification opens what it unlocked', () {
      expect(
        notification(type: 'program_membership_verified').route,
        '/profile/blueprint-bond',
      );
    });

    test('a type with nothing to open has no route', () {
      expect(notification(type: 'something_new').route, isNull);
    });
  });

  group('parsing', () {
    test('the target and actor id come off the wire', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'type': 'honors_attendance_open',
        'read': false,
        'created_at': '2026-09-18T14:00:00Z',
        'target_type': 'attendance_session',
        'target_id': 'sess-42',
        'actor': {'id': 'u9', 'display_name': 'Maya', 'avatar_url': 'a.jpg'},
      });

      expect(n.targetType, 'attendance_session');
      expect(n.targetId, 'sess-42');
      // Needed for the avatar cache scope — previously scoped by display name, so two people
      // with the same name shared a cache entry and a rename invalidated an unchanged avatar.
      expect(n.actorId, 'u9');
    });

    test('an older server that sends no target is fine', () {
      // Deploy order is server-before-client, but a client must not require fields a running
      // server may not send yet.
      final n = AppNotification.fromJson({
        'id': 'n1',
        'type': 'group_invite',
        'read': true,
        'created_at': '2026-09-18T14:00:00Z',
        'group': {'id': 'g1', 'name': 'CS Club'},
      });

      expect(n.targetType, isNull);
      expect(n.targetId, isNull);
      expect(n.route, '/groups/g1');
    });

    test('an unrecognised target type is treated as no target', () {
      // A type added server-side must not break a client that predates it: the row falls back to
      // whatever its notification type knows how to open.
      final n = notification(
        type: 'group_invite',
        groupId: 'g1',
        targetType: 'something_the_client_has_never_heard_of',
        targetId: 'x',
      );

      expect(n.route, '/groups/g1');
    });
  });
}

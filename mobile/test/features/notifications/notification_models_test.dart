import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/notifications/data/notification_models.dart';

Map<String, dynamic> _json(String type, {Map<String, dynamic>? group, Map<String, dynamic>? actor}) => {
      'id': 'n1',
      'type': type,
      'read': false,
      'created_at': '2026-07-24T10:00:00.000Z',
      'group': group,
      'actor': actor,
    };

void main() {
  group('AppNotification.fromJson', () {
    test('flattens group + actor', () {
      final n = AppNotification.fromJson(_json(
        'group_invite',
        group: {'id': 'g1', 'name': 'Chess Club'},
        actor: {'id': 'u1', 'display_name': 'Alex', 'avatar_url': null},
      ));
      expect(n.type, 'group_invite');
      expect(n.read, isFalse);
      expect(n.groupId, 'g1');
      expect(n.groupName, 'Chess Club');
      expect(n.actorName, 'Alex');
    });

    test('tolerates missing group/actor', () {
      final n = AppNotification.fromJson(_json('group_removed'));
      expect(n.groupId, isNull);
      expect(n.actorName, isNull);
    });
  });

  group('message rendering', () {
    AppNotification make(String type) => AppNotification.fromJson(_json(
          type,
          group: {'id': 'g1', 'name': 'CS Club'},
          actor: {'id': 'u1', 'display_name': 'Alex', 'avatar_url': null},
        ));

    test('invite names the actor and group', () {
      expect(make('group_invite').message, 'Alex invited you to CS Club');
    });
    test('approved', () => expect(make('group_request_approved').message, "You're now a member of CS Club"));
    test('made admin', () => expect(make('group_made_admin').message, "You're now an admin of CS Club"));
    test('removed as admin', () => expect(make('group_removed_admin').message, "You're no longer an admin of CS Club"));
    test('removed', () => expect(make('group_removed').message, 'You were removed from CS Club'));
    test('join request names the requester', () {
      expect(make('group_join_request').message, 'Alex requested to join CS Club');
    });

    test('falls back gracefully on unknown type / missing names', () {
      final n = AppNotification.fromJson(_json('something_new'));
      expect(n.message, 'You have a new notification');
      expect(AppNotification.fromJson(_json('group_invite')).message, 'Someone invited you to a group');
    });
  });
}

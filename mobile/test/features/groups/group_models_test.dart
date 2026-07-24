import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/groups/data/group_models.dart';

/// The role/permission helpers mirror the backend `policies.py`. They gate which admin
/// controls the UI shows, so a regression here would surface actions the server rejects
/// (or hide ones it allows). These are pure and cheap — worth locking down.
void main() {
  group('GroupRead permission getters', () {
    test('owner can manage and is owner', () {
      final g = GroupRead.fromJson(_json(myRole: 'owner'));
      expect(g.iAmOwner, isTrue);
      expect(g.iCanManage, isTrue);
    });

    test('admin can manage but is not owner', () {
      final g = GroupRead.fromJson(_json(myRole: 'admin'));
      expect(g.iAmOwner, isFalse);
      expect(g.iCanManage, isTrue);
    });

    test('plain member cannot manage', () {
      final g = GroupRead.fromJson(_json(myRole: 'member'));
      expect(g.iAmOwner, isFalse);
      expect(g.iCanManage, isFalse);
    });

    test('non-member (null role) cannot manage', () {
      final g = GroupRead.fromJson(_json(myRole: null));
      expect(g.iCanManage, isFalse);
    });
  });

  group('canModerate (must strictly outrank the target)', () {
    test('admin moderates a member', () => expect(canModerate('admin', 'member'), isTrue));
    test('admin cannot moderate another admin', () => expect(canModerate('admin', 'admin'), isFalse));
    test('owner can moderate an admin', () => expect(canModerate('owner', 'admin'), isTrue));
    test('the owner is never a valid target', () => expect(canModerate('owner', 'owner'), isFalse));
    test('a member moderates no one', () => expect(canModerate('member', 'member'), isFalse));
    test('a non-member moderates no one', () => expect(canModerate(null, 'member'), isFalse));
  });

  group('GroupMember.fromJson', () {
    test('flattens the nested profile', () {
      final m = GroupMember.fromJson({
        'user_id': 'u1',
        'profile': {'id': 'p1', 'user_id': 'u1', 'display_name': 'Alex', 'avatar_url': null, 'major': 'Math'},
        'role': 'admin',
        'status': 'active',
        'joined_at': '2026-01-01T00:00:00.000Z',
      });
      expect(m.userId, 'u1');
      expect(m.displayName, 'Alex');
      expect(m.major, 'Math');
      expect(m.isAdmin, isTrue);
      expect(m.isOwner, isFalse);
    });

    test('tolerates a null profile (falls back on the name)', () {
      final m = GroupMember.fromJson({
        'user_id': 'u2',
        'profile': null,
        'role': 'member',
        'status': 'requested',
        'joined_at': '2026-01-01T00:00:00.000Z',
      });
      expect(m.displayName, isNull);
      expect(m.nameOrFallback, 'LC Student');
    });
  });

  group('GroupSummary action state', () {
    GroupSummary summary({required String joinPolicy, String? myStatus}) => GroupSummary(
          id: 'g1',
          name: 'G',
          category: 'club',
          visibility: 'public',
          joinPolicy: joinPolicy,
          memberCount: 3,
          myStatus: myStatus,
        );

    test('open group → joinable', () {
      final g = summary(joinPolicy: 'open');
      expect(g.actionLabel, 'Join');
      expect(g.actionEnabled, isTrue);
    });
    test('approval group → request', () {
      expect(summary(joinPolicy: 'approval').actionLabel, 'Request');
    });
    test('invite-only → not directly joinable', () {
      expect(summary(joinPolicy: 'invite').actionEnabled, isFalse);
    });
    test('active member → Joined, not actionable', () {
      final g = summary(joinPolicy: 'open', myStatus: 'active');
      expect(g.actionLabel, 'Joined');
      expect(g.actionEnabled, isFalse);
    });
    test('banned → Unavailable, never offers a Join that would 403', () {
      final g = summary(joinPolicy: 'open', myStatus: 'banned');
      expect(g.actionLabel, 'Unavailable');
      expect(g.actionEnabled, isFalse);
    });
  });

  group('roleRank', () {
    test('orders owner > admin > member', () {
      expect(roleRank('owner') > roleRank('admin'), isTrue);
      expect(roleRank('admin') > roleRank('member'), isTrue);
    });
  });
}

Map<String, dynamic> _json({required String? myRole}) => {
      'id': 'g1',
      'name': 'CS Club',
      'avatar_url': null,
      'category': 'club',
      'visibility': 'public',
      'join_policy': 'open',
      'member_count': 3,
      'max_members': null,
      'my_status': 'active',
      'description': 'hi',
      'owner_id': 'u-owner',
      'conversation_id': 'c1',
      'my_role': myRole,
    };

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/notifications/data/notification_models.dart';

/// A reaction is the first notification whose row has to name a value carried by the event
/// itself — which emoji — and the first that deep-links into a conversation.
void main() {
  AppNotification build({
    String? detail,
    String? targetType = 'dm',
    String? targetId = 'match-1',
    String? actorName = 'Alex',
  }) =>
      AppNotification.fromJson({
        'id': 'n1',
        'type': 'message_reaction',
        'read': false,
        'created_at': '2026-09-19T10:00:00Z',
        'actor': actorName == null ? null : {'id': 'u2', 'display_name': actorName},
        'target_type': targetType,
        'target_id': targetId,
        'detail': detail,
      });

  group('the sentence', () {
    test('names the emoji when the server sent one', () {
      expect(build(detail: '❤️').message, 'Alex reacted ❤️ to your message');
    });

    test('falls back cleanly for rows written before detail existed', () {
      // The column is new and nullable, so older rows have no emoji. Interpolating a null here
      // would print the word "null" into the notification list.
      expect(build().message, 'Alex reacted to your message');
      expect(build().message, isNot(contains('null')));
    });

    test('an unknown actor still reads as a sentence', () {
      expect(build(detail: '👍', actorName: null).message,
          'Someone reacted 👍 to your message');
    });
  });

  group('the route', () {
    test('a DM opens the DM chat, addressed by match id', () {
      expect(build(detail: '👍').route, '/chat/match-1');
    });

    test('a group opens the group chat', () {
      // Two segments, so it can never be matched as a DM id.
      expect(
        build(detail: '👍', targetType: 'group_chat', targetId: 'conv-9').route,
        '/chat/group/conv-9',
      );
    });

    test('the type decides, so the client never guesses DM-vs-group', () {
      // `openMessageConversation` inferred this from the loaded thread list and opened the DM
      // route for a group on a cold start. The server now states it.
      final group = build(detail: '👍', targetType: 'group_chat', targetId: 'x');
      final dm = build(detail: '👍', targetType: 'dm', targetId: 'x');
      expect(group.route, isNot(dm.route));
    });

    test('a row with no target opens nothing rather than a broken route', () {
      expect(build(detail: '👍', targetId: null).route, isNull);
    });
  });

  test('a reaction row shows the actor, not a type icon', () {
    expect(build(detail: '👍').isActorCentric, isTrue);
  });
}

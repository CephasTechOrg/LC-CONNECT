import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';

/// Report #4 — reactions. These cover the chip arithmetic, which is where an optimistic toggle
/// goes subtly wrong: the count and "did I react" move independently, and a chip can be shared
/// with other people whose tallies must survive this viewer's toggle.
void main() {
  group('ReactionSummary.toggled', () {
    test('reacting adds me and increments', () {
      const chip = ReactionSummary(emoji: '👍', count: 2, reactedByMe: false);

      final next = chip.toggled()!;

      expect(next.count, 3);
      expect(next.reactedByMe, isTrue);
    });

    test('un-reacting removes me and decrements', () {
      const chip = ReactionSummary(emoji: '👍', count: 3, reactedByMe: true);

      final next = chip.toggled()!;

      expect(next.count, 2);
      expect(next.reactedByMe, isFalse);
    });

    test('the last reactor removing theirs drops the chip', () {
      // A chip reading "👍 0" would be worse than no chip.
      const chip = ReactionSummary(emoji: '👍', count: 1, reactedByMe: true);

      expect(chip.toggled(), isNull);
    });

    test("un-reacting never removes a chip other people are in", () {
      // The case an over-eager rollback gets wrong: my removal must leave their tally standing.
      const chip = ReactionSummary(emoji: '👍', count: 4, reactedByMe: true);

      final next = chip.toggled()!;

      expect(next, isNotNull);
      expect(next.count, 3);
    });
  });

  group('parsing', () {
    test('a message carries its aggregated reactions', () {
      final message = ChatMessage.fromJson({
        'id': 'srv-1',
        'match_id': 'm1',
        'sender_id': 'me',
        'body': 'hi',
        'created_at': '2026-09-18T10:00:00Z',
        'read_at': null,
        'reactions': [
          {'emoji': '👍', 'count': 2, 'reacted_by_me': true},
          {'emoji': '❤️', 'count': 1, 'reacted_by_me': false},
        ],
      });

      expect(message.reactions, hasLength(2));
      expect(message.reactions.first.emoji, '👍');
      expect(message.reactions.first.count, 2);
      expect(message.reactions.first.reactedByMe, isTrue);
    });

    test('a message with no reactions parses to an empty list, not null', () {
      // The overwhelming majority of messages. An empty list keeps every call site free of a
      // null check.
      final message = ChatMessage.fromJson({
        'id': 'srv-1',
        'match_id': 'm1',
        'sender_id': 'me',
        'body': 'hi',
        'created_at': '2026-09-18T10:00:00Z',
        'read_at': null,
      });

      expect(message.reactions, isEmpty);
    });

    test('a server that predates reactions is fine', () {
      // Deploy order is server-before-client, but a client must never require a field a running
      // server may not send.
      final message = ChatMessage.fromJson({
        'id': 'srv-1',
        'match_id': 'm1',
        'sender_id': 'me',
        'body': 'hi',
        'created_at': '2026-09-18T10:00:00Z',
        'read_at': null,
        'reactions': null,
      });

      expect(message.reactions, isEmpty);
    });
  });

  group('copyWith', () {
    test('reactions can be replaced without touching anything else', () {
      final message = ChatMessage(
        id: 'srv-1',
        matchId: 'm1',
        senderId: 'me',
        body: 'hi',
        createdAt: DateTime.utc(2026, 9, 18, 10),
        delivered: true,
        status: MessageStatus.sent,
      );

      final next = message.copyWith(
        reactions: const [ReactionSummary(emoji: '👍', count: 1, reactedByMe: true)],
      );

      expect(next.reactions, hasLength(1));
      expect(next.delivered, isTrue, reason: 'unrelated state must survive');
      expect(next.body, 'hi');
    });

    test('omitting reactions keeps the existing ones', () {
      final message = ChatMessage(
        id: 'srv-1',
        matchId: 'm1',
        senderId: 'me',
        body: 'hi',
        createdAt: DateTime.utc(2026, 9, 18, 10),
        reactions: const [ReactionSummary(emoji: '👍', count: 1, reactedByMe: true)],
      );

      expect(message.copyWith(delivered: true).reactions, hasLength(1));
    });
  });
}

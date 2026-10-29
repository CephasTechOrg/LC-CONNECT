import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/thread_preview.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';

const _me = 'me';
final _t0 = DateTime.utc(2026, 10, 1, 12);

ChatMessage _msg({String sender = 'them', String body = 'see you at 5', bool deleted = false}) =>
    ChatMessage(id: 'm1', matchId: 'c1', senderId: sender, body: body, createdAt: _t0, deleted: deleted);

MessageThread _dm({ChatMessage? latest, ThreadReactionPreview? reaction}) => MessageThread(
      conversationId: 'c1',
      kind: 'dm',
      matchId: 'match-1',
      partner: const MessagePartner(
        profileId: 'p1',
        userId: 'them',
        displayName: 'Ama Mensah',
        interests: [],
        lookingFor: [],
        languagesSpoken: [],
        languagesLearning: [],
      ),
      latestMessage: latest,
      latestReaction: reaction,
    );

ThreadReactionPreview _reaction({
  String actor = 'them',
  String? actorName,
  String? sender = _me,
  String snippet = 'see you at 5',
  DateTime? at,
}) =>
    ThreadReactionPreview(
      emoji: '👍',
      actorId: actor,
      actorName: actorName,
      messageId: 'm1',
      messageSenderId: sender,
      messageSnippet: snippet,
      reactedAt: at ?? _t0.add(const Duration(minutes: 1)),
    );

void main() {
  test('a newer reaction to my message names the reactor and quotes the message', () {
    final line = threadPreview(_dm(latest: _msg(sender: _me), reaction: _reaction()), _me);
    expect(line.text, 'Ama reacted 👍 to your message “see you at 5”');
    expect(line.italic, isFalse);
  });

  test('my own reaction reads "You reacted"', () {
    final line = threadPreview(
      _dm(latest: _msg(), reaction: _reaction(actor: _me, sender: 'them')),
      _me,
    );
    expect(line.text, 'You reacted 👍 to “see you at 5”');
  });

  test('in a group, the frame carries the reactor name', () {
    final group = MessageThread(
      conversationId: 'g1',
      kind: 'group',
      groupName: 'Study group',
      latestMessage: _msg(sender: 'kofi'),
      latestReaction: _reaction(actor: 'kofi', actorName: 'Kofi Boateng', sender: 'abena', snippet: 'notes'),
    );
    expect(threadPreview(group, _me).text, 'Kofi reacted 👍 to “notes”');
  });

  test('a reaction older than the latest message gives way to the message', () {
    final line = threadPreview(
      _dm(latest: _msg(body: 'newer'), reaction: _reaction(at: _t0.subtract(const Duration(minutes: 1)))),
      _me,
    );
    expect(line.text, 'newer');
  });

  test('an older server sends no sender id — its previews were always of my messages', () {
    final line = threadPreview(_dm(latest: _msg(), reaction: _reaction(sender: null, snippet: '')), _me);
    expect(line.text, 'Ama reacted 👍 to your message');
  });

  test('a deleted latest message reads as a quiet note, not blank', () {
    expect(threadPreview(_dm(latest: _msg(deleted: true, body: '')), _me),
        (text: 'This message was deleted', italic: true));
    expect(threadPreview(_dm(latest: _msg(sender: _me, deleted: true, body: '')), _me).text,
        'You deleted this message');
  });

  test('my latest message is prefixed "You:" and flattened to one line', () {
    expect(threadPreview(_dm(latest: _msg(sender: _me, body: 'on my\nway')), _me).text, 'You: on my way');
  });

  test('an empty chat invites a first message', () {
    expect(threadPreview(_dm(), _me), (text: 'No messages yet — say hello', italic: true));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/groups/data/group_models.dart';
import 'package:lc_connect/features/groups/widgets/your_groups_section.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';

GroupSummary _g(String id) => GroupSummary(
      id: id,
      name: id,
      category: 'club',
      visibility: 'public',
      joinPolicy: 'open',
      memberCount: 3,
      myStatus: 'active',
      chatId: 'c-$id',
    );

MessageThread _t(String id, int minutesAgo) => MessageThread(
      conversationId: 'c-$id',
      kind: 'group',
      latestMessage: ChatMessage(
        id: 'm-$id',
        matchId: 'c-$id',
        senderId: 'u',
        body: 'hi',
        createdAt: DateTime(2026, 10, 29, 12).subtract(Duration(minutes: minutesAgo)),
      ),
    );

void main() {
  test('your groups list the busiest conversation first, quiet ones after in server order', () {
    final ordered = sortByActivity(
      [_g('quiet'), _g('old'), _g('new'), _g('silent')],
      {'c-old': _t('old', 90), 'c-new': _t('new', 5)},
    );
    expect(ordered.map((g) => g.id), ['new', 'old', 'quiet', 'silent']);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/reaction_state.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';

ReactionSummary _r(String emoji, int count, {bool mine = false}) =>
    ReactionSummary(emoji: emoji, count: count, reactedByMe: mine);

String _show(List<ReactionSummary> chips) =>
    chips.map((c) => '${c.emoji}${c.count}${c.reactedByMe ? '*' : ''}').join(' ');

void main() {
  group('one reaction per person', () {
    test('picking a new emoji moves my reaction instead of adding a second', () {
      final next = toggleMine([_r('👍', 2, mine: true), _r('❤️', 1)], '❤️');
      expect(_show(next), '👍1 ❤️2*');
    });

    test('picking my current emoji removes it, and an emptied chip disappears', () {
      expect(toggleMine([_r('😂', 1, mine: true)], '😂'), isEmpty);
    });

    test('a first reaction adds a chip in picker order', () {
      expect(_show(toggleMine([_r('🙏', 1)], '👍')), '👍1* 🙏1');
    });

    test('myEmoji finds mine or null', () {
      expect(myEmoji([_r('👍', 1), _r('😮', 1, mine: true)]), '😮');
      expect(myEmoji([_r('👍', 1)]), isNull);
    });
  });

  test('applyState rebuilds the strip from a server tally, dropping zero counts', () {
    final next = applyState([(emoji: '🙏', count: 1), (emoji: '👍', count: 3), (emoji: '😢', count: 0)], '👍');
    expect(_show(next), '👍3* 🙏1');
  });
}

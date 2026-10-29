/// One person's reaction on a message, as the chip strip shows it — pure, so the rules are
/// testable without a widget.
///
/// One reaction per person (WhatsApp): picking a different emoji *moves* my reaction rather than
/// adding a second chip, and picking my current one removes it.
library;

import 'message_models.dart';
import 'reaction_choices.dart';

/// The emoji I reacted with, or null.
String? myEmoji(List<ReactionSummary> chips) {
  for (final c in chips) {
    if (c.reactedByMe) return c.emoji;
  }
  return null;
}

/// The strip after I tap [emoji]: remove it if it is mine, otherwise move my reaction to it.
List<ReactionSummary> toggleMine(List<ReactionSummary> chips, String emoji) {
  final mine = myEmoji(chips);
  final next = <ReactionSummary>[];
  for (final c in chips) {
    if (c.emoji == mine) {
      // Take my old reaction out of its chip.
      if (c.count > 1) next.add(ReactionSummary(emoji: c.emoji, count: c.count - 1, reactedByMe: false));
    } else {
      next.add(c);
    }
  }
  if (mine == emoji) return next; // tapping my own reaction removes it
  final at = next.indexWhere((c) => c.emoji == emoji);
  if (at == -1) {
    next.add(ReactionSummary(emoji: emoji, count: 1, reactedByMe: true));
  } else {
    next[at] = ReactionSummary(emoji: emoji, count: next[at].count + 1, reactedByMe: true);
  }
  next.sort((a, b) => reactionOrder(a.emoji).compareTo(reactionOrder(b.emoji)));
  return next;
}

/// The strip from a server tally (no viewer flag) plus which emoji, if any, is mine.
List<ReactionSummary> applyState(List<({String emoji, int count})> counts, String? mine) {
  final next = [
    for (final c in counts)
      if (c.count > 0) ReactionSummary(emoji: c.emoji, count: c.count, reactedByMe: c.emoji == mine),
  ];
  next.sort((a, b) => reactionOrder(a.emoji).compareTo(reactionOrder(b.emoji)));
  return next;
}

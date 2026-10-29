/// The reactions a user may choose, in picker order. Mirrors `REACTION_ALLOWLIST` server-side,
/// which is the authority — anything else is refused with a 422 (pinned by
/// `backend/tests/test_reaction_allowlist_parity.py`).
const kReactionChoices = <String>['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Sort key that keeps a chip strip in picker order; emoji no longer offered sort last.
int reactionOrder(String emoji) {
  final i = kReactionChoices.indexOf(emoji);
  return i == -1 ? kReactionChoices.length : i;
}

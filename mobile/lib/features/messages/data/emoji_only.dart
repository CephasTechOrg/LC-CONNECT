// The analyzer's regexp check predates Unicode property escapes; these compile and are covered by
// test/features/messages/emoji_only_test.dart.
// ignore_for_file: valid_regexps

final _emojiOnly = RegExp(
  r'^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|\p{Regional_Indicator}|\u200D|\uFE0F|\s)+$',
  unicode: true,
);
final _pictograph = RegExp(r'\p{Extended_Pictographic}|\p{Regional_Indicator}{2}', unicode: true);

/// Up to [max] emoji and nothing else — the chat draws these large, without a bubble.
///
/// Counts pictographs rather than grapheme clusters, so a ZWJ family or a skin-tone variant
/// counts as its parts; that only makes the cutoff slightly stricter, never wrong.
bool isEmojiOnly(String text, {int max = 3}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !_emojiOnly.hasMatch(trimmed)) return false;
  final count = _pictograph.allMatches(trimmed).length;
  return count > 0 && count <= max;
}

/// The Blueprint Bond completeness minimums, mirrored from the server
/// (`backend/app/shared/scholar_profile.py`; kept in step by `tests/test_scholar_rules_parity.py`).
///
/// The editor used to hide these: a student could write a 60-character summary or two skills,
/// tap Save, and watch "3 of 6 done" never move with no idea why. Showing the same numbers the
/// server checks, live as they type, makes the requirement visible before it is a rejection.
library;

const int kMinSummaryChars = 80;
const int kMinSkills = 3;
const int kMinCareerInterests = 1;

/// Splits what a student typed into tags: "Python, SQL; Excel" is three skills, not one.
///
/// Trims each piece, drops empties, and de-duplicates case-insensitively (keeping the first
/// spelling) against [existing] as well as within the input.
List<String> splitTags(String raw, {Iterable<String> existing = const []}) {
  final seen = {for (final e in existing) e.toLowerCase()};
  final out = <String>[];
  for (final piece in raw.split(RegExp(r'[,;\n]'))) {
    final tag = piece.trim();
    if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
    out.add(tag);
  }
  return out;
}

/// "42 / 80 characters" while short, "Looks good" once the summary meets the minimum.
String summaryProgress(String summary) {
  final n = summary.trim().length;
  return n >= kMinSummaryChars ? 'Looks good' : '$n / $kMinSummaryChars characters minimum';
}

/// "Add at least 3 · 1 so far" while short, null once the minimum is met.
String? tagProgress(int count, int minimum) =>
    count >= minimum ? null : 'Add at least $minimum · $count so far';

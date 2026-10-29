import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/scholars/data/blueprint_rules.dart';

/// The rules behind the "3 of 6 done that never moves" report: a comma-separated line used to be
/// one skill, and the minimums the server checks were never shown.
void main() {
  group('splitTags', () {
    test('commas, semicolons and new lines each end a tag', () {
      expect(splitTags('Python, SQL; Excel\nPublic speaking'), [
        'Python',
        'SQL',
        'Excel',
        'Public speaking',
      ]);
    });

    test('drops blanks and duplicates, including ones already added', () {
      expect(splitTags(' python, , Python ,SQL', existing: ['sql']), ['python']);
    });
  });

  test('summary progress counts toward the server minimum', () {
    expect(summaryProgress('short'), '5 / $kMinSummaryChars characters minimum');
    expect(summaryProgress('x' * kMinSummaryChars), 'Looks good');
  });

  test('tag progress shows only while short', () {
    expect(tagProgress(1, kMinSkills), 'Add at least $kMinSkills · 1 so far');
    expect(tagProgress(kMinSkills, kMinSkills), isNull);
  });
}

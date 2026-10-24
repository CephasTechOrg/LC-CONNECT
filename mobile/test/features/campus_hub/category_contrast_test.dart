import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/widgets/campus_post_style.dart';

/// Categories share one tint so a list of them reads as one list, not competing colours (see
/// campus_post_style.dart). This pins both halves: every category uses the same pair, and that
/// pair is readable — the accent doubles as text on the tint, so it is held to AA.
double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _luminance(a), y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  final categories = [
    for (final key in announcementCategoryIcons.keys) ('announcement', key),
    for (final key in opportunityCategoryIcons.keys) ('opportunity', key),
    ('announcement', null),
    ('opportunity', null),
  ];

  test('every category shares one tint', () {
    final pairs = {
      for (final (kind, key) in categories)
        () {
          final (accent, tint, _) = campusCategoryStyle(kind, key);
          return (accent, tint);
        }(),
    };
    expect(pairs, hasLength(1));
  });

  test('that tint is readable as text (AA)', () {
    final (accent, tint, _) = campusCategoryStyle('announcement', 'academic');
    expect(_contrast(accent, tint), greaterThanOrEqualTo(4.5));
  });
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/theme/app_theme.dart';

/// The contrast audit from report #18 (4.7), as a checked property rather than an opinion.
///
/// The review guessed that `textMuted` on `background` would be the problem at the 10–12px sizes
/// used for timestamps. Measured, it is the opposite: `textMuted` passes (4.57:1, narrowly) and
/// the **semantic colours** are the failures. Worth recording that the guess was wrong, because
/// the instinct to eyeball contrast is exactly what these numbers replace.
///
/// WCAG 2.1 AA: 4.5:1 for normal text, 3:1 for large text (≥18pt, or ≥14pt bold) and for the
/// boundary of a UI component.
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color fg, Color bg) {
  final a = _relativeLuminance(fg);
  final b = _relativeLuminance(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  const grounds = {
    'background': AppColors.background,
    'surface': AppColors.surface,
  };

  group('text colours meet AA for normal text', () {
    // These carry body copy, titles and metadata — the text a user actually reads.
    const readable = {
      'textDark': AppColors.textDark,
      'textMid': AppColors.textMid,
      'textMuted': AppColors.textMuted,
    };

    for (final ground in grounds.entries) {
      for (final fg in readable.entries) {
        test('${fg.key} on ${ground.key}', () {
          expect(
            contrast(fg.value, ground.value),
            greaterThanOrEqualTo(4.5),
            reason: '${fg.key} on ${ground.key} is below AA for normal text',
          );
        });
      }
    }

    test('textMuted has almost no headroom, so it must not be darkened-by-accident', () {
      // 4.57:1 on `background`. Any lightening of this colour, or any darkening of the page
      // ground, drops the app's timestamps and metadata below AA. This test is the tripwire.
      final measured = contrast(AppColors.textMuted, AppColors.background);
      expect(measured, greaterThanOrEqualTo(4.5));
      expect(measured, lessThan(5.0), reason: 'if this rose, the comment above is stale');
    });
  });

  group('known contrast exceptions — recorded, not hidden', () {
    // These fail AA for normal text today. Changing them is a brand decision, so the failures are
    // pinned here rather than silently tolerated: the numbers may not get *worse* without a test
    // going red and someone deciding deliberately.
    //
    // Candidate replacements that pass 4.5:1 on both grounds, if the palette is revisited:
    //   primary #3F7FB5 → #3B77AA   error #EF4444 → #CD3A3A   green #10B981 → #0B815A
    const exceptions = {
      'primary': (AppColors.primary, 4.0),
      'error': (AppColors.error, 3.5),
      'green': (AppColors.green, 2.35),
    };

    for (final entry in exceptions.entries) {
      test('${entry.key} is no worse than its recorded ratio', () {
        final (color, floor) = entry.value;
        expect(
          contrast(color, AppColors.background),
          greaterThanOrEqualTo(floor),
          reason: '${entry.key} contrast regressed below its recorded value',
        );
      });
    }

    test('primary and error clear AA for large text at least', () {
      // Both are used on titles and buttons as well as inline, so 3:1 is the floor that keeps
      // those uses defensible while the palette question is open.
      expect(contrast(AppColors.primary, AppColors.background), greaterThanOrEqualTo(3.0));
      expect(contrast(AppColors.error, AppColors.background), greaterThanOrEqualTo(3.0));
    });

    test('green fails even the large-text floor — the one genuine finding here', () {
      // 2.40:1. It marks "checked in" for attendance and "Published" for a campus post, so it
      // carries state, not decoration. Documented as failing so it reads as a known debt with a
      // ready fix (#0B815A) rather than as an oversight.
      expect(contrast(AppColors.green, AppColors.background), lessThan(3.0));
    });
  });

  group('non-text colours', () {
    test('border is a hairline, not a boundary that conveys state', () {
      // 1.14:1, far below the 3:1 WCAG asks for a *meaningful* component boundary. Acceptable
      // only because nothing here depends on seeing the border to understand or operate the UI —
      // cards also differ from the page by fill. If a control's only affordance ever becomes its
      // border, this needs revisiting.
      expect(contrast(AppColors.border, AppColors.background), lessThan(3.0));
    });
  });
}

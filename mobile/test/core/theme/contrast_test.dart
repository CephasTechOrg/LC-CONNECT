import 'dart:math' as math;

import 'package:flutter/material.dart';
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

  group('primaryText — the brand blue as text', () {
    // `primary` is 4.0:1 (see the exceptions below), so links, "See all", the selected tab label
    // and date-block months use this shade instead. It must clear AA on every ground it sits on,
    // including the pale-blue tiles.
    const grounds = {
      'background': AppColors.background,
      'surface': AppColors.surface,
      'primarySoft': AppColors.primarySoft,
    };
    for (final ground in grounds.entries) {
      test('primaryText on ${ground.key}', () {
        expect(contrast(AppColors.primaryText, ground.value), greaterThanOrEqualTo(4.5));
      });
    }

    // testWidgets, not test: building the theme builds DM Sans styles, and google_fonts' failed
    // offline fetch only stays contained under the widget binding (see design_tokens_test).
    testWidgets('navigation labels are readable text colours', (tester) async {
      // The unselected tab label was #9CA3AF — 2.5:1 on the white bar.
      final nav = AppTheme.light.bottomNavigationBarTheme;
      expect(contrast(nav.selectedItemColor!, AppColors.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(nav.unselectedItemColor!, AppColors.surface), greaterThanOrEqualTo(4.5));
    });
  });

  group('status colours pass AA as text and under white text', () {
    // They were the recorded exceptions here: error #EF4444 at 3.5:1 and green #10B981 at 2.4:1,
    // and screens had begun defining their own darker copies one by one. The tokens themselves now
    // pass, so a plain `AppColors.error` or `AppColors.green` is safe wherever it lands.
    for (final entry in {
      'error': AppColors.error,
      'errorText': AppColors.errorText,
      'green': AppColors.green,
      'warning': AppColors.warning,
    }.entries) {
      test('${entry.key} on the page, on white, and with white text on it', () {
        expect(contrast(entry.value, AppColors.background), greaterThanOrEqualTo(4.5));
        expect(contrast(entry.value, AppColors.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(Colors.white, entry.value), greaterThanOrEqualTo(4.5));
      });
    }

    test('each status text shade passes on its own tint', () {
      expect(contrast(AppColors.errorText, AppColors.errorSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.green, AppColors.greenSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.warning, AppColors.warningSoft), greaterThanOrEqualTo(4.5));
    });
  });

  group('known contrast exceptions — recorded, not hidden', () {
    // The brand blue fails AA for normal text. It stays for fills, icons and large headings —
    // a brand decision — and text uses [AppColors.primaryText]. Pinned so it cannot get worse
    // without a test going red.
    test('primary is no worse than its recorded ratio, and clears the large-text floor', () {
      expect(contrast(AppColors.primary, AppColors.background), greaterThanOrEqualTo(4.0));
      expect(contrast(AppColors.primary, AppColors.background), greaterThanOrEqualTo(3.0));
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

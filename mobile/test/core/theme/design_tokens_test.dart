import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/theme/app_radii.dart';
import 'package:lc_connect/core/theme/app_spacing.dart';
import 'package:lc_connect/core/theme/app_typography.dart';
import 'package:lc_connect/core/theme/app_theme.dart';

/// Report #18, the foundation item.
///
/// Extracting tokens is the easy half; the hard half is that they stay the source of truth. The
/// app arrived at fifteen radii and twenty-four font sizes precisely because nothing stopped a
/// one-off, so these are the tripwires — a new half-step or an unwired component theme fails here
/// rather than shipping and being discovered by eye months later.
void main() {
  // Anything that builds a `TextStyle` runs as `testWidgets`, not `test`, and that is not
  // cosmetic. `google_fonts` fetches DM Sans over HTTP on first use; there is no network in a
  // test run, so the fetch fails asynchronously. `testWidgets` reports that failure against the
  // widget binding — which is why the rest of this suite has always tolerated it — whereas in a
  // plain `test` the error escapes to the zone and fails the test after it has already passed.
  // The assertions below are about metrics (size, weight, height), which are on the style whether
  // or not the glyphs ever load.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Built inside tests, not at group level, for the reason above.
  Map<String, TextStyle> roles() => <String, TextStyle>{
      'display': AppTypography.display,
      'titleLarge': AppTypography.titleLarge,
      'title': AppTypography.title,
      'titleSmall': AppTypography.titleSmall,
      'bodyLarge': AppTypography.bodyLarge,
      'body': AppTypography.body,
      'bodySmall': AppTypography.bodySmall,
      'label': AppTypography.label,
      'caption': AppTypography.caption,
      'micro': AppTypography.micro,
    };

  group('type scale', () {
    testWidgets('every role sits on the declared scale', (tester) async {
      // The half-steps this replaced (9.5, 10.5, 12.5, 13.5, 14.5, 15.5) were ad-hoc tuning, and
      // a new one added here would quietly restart that.
      for (final entry in roles().entries) {
        expect(
          AppTypography.scale,
          contains(entry.value.fontSize),
          reason: '${entry.key} is ${entry.value.fontSize}, which is not on the scale',
        );
      }
    });

    test('the scale has no fractional sizes', () {
      for (final size in AppTypography.scale) {
        expect(size, size.roundToDouble());
      }
    });

    testWidgets('roles are distinct and ordered largest to smallest', (tester) async {
      // Two roles at the same size means one of them is not carrying information.
      final sizes = roles().values.map((s) => s.fontSize!).toList();
      expect(sizes.toSet().length, sizes.length, reason: 'two roles share a size');
      expect(sizes, orderedEquals(List.of(sizes)..sort((a, b) => b.compareTo(a))));
    });

    test('nothing is smaller than 10', () {
      // Below this, text stops being readable on a phone at arm's length.
      expect(AppTypography.scale.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(10));
    });

    testWidgets('every role sets a line height', (tester) async {
      // A null height falls back to the font's own metrics, which differ per role and produce the
      // uneven vertical rhythm this scale exists to fix.
      for (final entry in roles().entries) {
        expect(entry.value.height, isNotNull, reason: '${entry.key} has no line height');
      }
    });

    testWidgets('small roles are heavier, because weight carries them rather than size', (tester) async {
      expect(AppTypography.micro.fontWeight!.value,
          greaterThan(AppTypography.body.fontWeight!.value));
      expect(AppTypography.label.fontWeight!.value,
          greaterThan(AppTypography.body.fontWeight!.value));
    });

    testWidgets('a role carries no colour of its own', (tester) async {
      // A role says how big and how heavy. The same label is muted on one surface and inverted on
      // another, so colour belongs to the theme.
      for (final entry in roles().entries) {
        expect(entry.value.color, isNull, reason: '${entry.key} hardcodes a colour');
      }
    });
  });

  group('the theme is actually wired to the tokens', () {
    // Without this the tokens are documentation: a component theme could keep its own hardcoded
    // size and nothing would notice.

    testWidgets('textTheme comes from AppTypography', (tester) async {
      final theme = AppTheme.light;
      expect(theme.textTheme.bodyMedium?.fontSize, AppTypography.body.fontSize);
      expect(theme.textTheme.titleLarge?.fontSize, AppTypography.title.fontSize);
      expect(theme.textTheme.labelSmall?.fontSize, AppTypography.micro.fontSize);
    });

    testWidgets('textTheme carries the app text colour', (tester) async {
      final theme = AppTheme.light;
      expect(theme.textTheme.bodyMedium?.color, AppColors.textDark);
    });

    testWidgets('component text styles are on the scale', (tester) async {
      final theme = AppTheme.light;
      final styles = <String, TextStyle?>{
        'appBar title': theme.appBarTheme.titleTextStyle,
        'filled button': theme.filledButtonTheme.style?.textStyle?.resolve({}),
        'outlined button': theme.outlinedButtonTheme.style?.textStyle?.resolve({}),
        'input label': theme.inputDecorationTheme.labelStyle,
        'input hint': theme.inputDecorationTheme.hintStyle,
        'nav selected': theme.bottomNavigationBarTheme.selectedLabelStyle,
        'nav unselected': theme.bottomNavigationBarTheme.unselectedLabelStyle,
      };
      for (final entry in styles.entries) {
        expect(entry.value?.fontSize, isNotNull, reason: '${entry.key} has no size');
        expect(AppTypography.scale, contains(entry.value!.fontSize),
            reason: '${entry.key} is ${entry.value!.fontSize}, off the scale');
      }
    });

    testWidgets('component radii are on the radius scale', (tester) async {
      final theme = AppTheme.light;
      final radii = <double>[AppRadii.hairline, AppRadii.xs, AppRadii.sm, AppRadii.md,
          AppRadii.lg, AppRadii.card, AppRadii.xl, AppRadii.sheet, AppRadii.full];
      final card = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(radii, contains((card.borderRadius as BorderRadius).topLeft.x));
    });
  });

  group('spacing grid', () {
    test('every step is a multiple of 4', () {
      // A value off the grid is what produced `fromLTRB(20, 4, 20, 8)` next to
      // `fromLTRB(20, 12, 20, 4)` on adjacent dashboard cards.
      for (final step in [
        AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.lg,
        AppSpacing.xl, AppSpacing.xxl, AppSpacing.xxxl, AppSpacing.gutter,
      ]) {
        expect(step % 4, 0, reason: '$step is not on the 4px grid');
      }
    });

    test('the page gutter is a single value for the whole app', () {
      // Inconsistent gutters are the most visible alignment error there is — content that shifts
      // sideways as you move between screens.
      expect(AppSpacing.pagePadding.left, AppSpacing.gutter);
      expect(AppSpacing.pagePadding.right, AppSpacing.gutter);
    });
  });
}

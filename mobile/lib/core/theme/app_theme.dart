import 'package:flutter/material.dart';

import 'app_radii.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppColors {
  static const primary    = Color(0xFF3F7FB5);
  static const primaryLight = Color(0xFF8CB0BF);
  /// [primary] as *text*. The brand blue itself is 4.0:1 on the page — under AA (4.5:1) for
  /// normal text — so it stays for fills, icons and large headings, and links and labels use
  /// this one shade deeper. Passes on surface (5.1), background (4.8) and [primarySoft] (4.56).
  static const primaryText  = Color(0xFF3772A4);
  static const primarySoft  = Color(0xFFEBF3F9);
  static const primaryPale  = Color(0xFFEFF6FB);
  static const background = Color(0xFFF6F9FB);
  static const surface    = Color(0xFFFFFFFF);
  static const border     = Color(0xFFE5EAF0);
  // Status colours. Each has a fill/text shade that passes AA (4.5:1) on white and as white text,
  // a deeper text shade for use *on its own tint*, and the tint itself. They were #EF4444 (3.8:1)
  // and #10B981 (2.5:1), so screens had started defining their own darker copies one by one.
  static const error      = Color(0xFFDC2626);
  static const errorText  = Color(0xFFB91C1C);
  static const errorSoft  = Color(0xFFFEE2E2);
  static const green      = Color(0xFF15803D);
  static const greenSoft  = Color(0xFFDCFCE7);
  static const warning    = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFEF3C7);
  /// The flat grey of a secondary pill (Decline, Withdraw) and of a neutral status chip.
  static const quiet      = Color(0xFFEEF2F6);
  static const textDark   = Color(0xFF111827);
  static const textMid    = Color(0xFF374151);
  static const textMuted  = Color(0xFF6B7280);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      // Built from [AppTypography] rather than from Material's defaults, so a plain `Text` and a
      // `Theme.of(context).textTheme` lookup both land on the app's own scale. Colour is applied
      // here and not in the token: a role says how big and how heavy, never what colour.
      textTheme: AppTypography.textTheme.apply(
        bodyColor: AppColors.textDark,
        displayColor: AppColors.textDark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        centerTitle: false,
        // Was a one-off 17 — the only use of that size in the app. `title` (18) is the role.
        titleTextStyle: AppTypography.title.copyWith(color: AppColors.textDark),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.all(AppRadii.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          // The full pill every redesigned page settled on (Join, Publish, Create activity,
          // Accept). As the theme default, a plain `FilledButton` gets it without restating it.
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.full),
          ),
          textStyle: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textDark,
          side: const BorderSide(color: AppColors.border, width: 1.5),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.full),
          ),
          textStyle: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      // Links and quiet actions: the AA blue, on a full 48dp target.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryText,
          minimumSize: const Size(48, 48),
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      // One pop-up message style. Screens set colour where it means something (error, success);
      // shape, position and type come from here instead of being restated at every call site.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textDark,
        contentTextStyle: AppTypography.body.copyWith(color: Colors.white),
        actionTextColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.lg)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.sheet)),
        titleTextStyle: AppTypography.title.copyWith(color: AppColors.textDark),
        contentTextStyle: AppTypography.body.copyWith(color: AppColors.textMid, height: 1.45),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        // Was 14/13 — neither on any grid. On the scale this is 16/12, which is a pixel-level
        // change to the field's height and the closest honest equivalent.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.all(AppRadii.lg),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: AppTypography.body.copyWith(color: AppColors.textMuted),
        hintStyle: AppTypography.body.copyWith(color: AppColors.textMuted),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        // Text colours, not the brand fill: these are 10px labels. The old unselected grey
        // (#9CA3AF) was 2.5:1 on white — the least legible text in the app.
        selectedItemColor: AppColors.primaryText,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: AppTypography.micro,
        unselectedLabelStyle: AppTypography.micro.copyWith(fontWeight: FontWeight.w400),
      ),
    );
  }
}

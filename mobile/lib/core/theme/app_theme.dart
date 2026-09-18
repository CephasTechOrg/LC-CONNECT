import 'package:flutter/material.dart';

import 'app_radii.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppColors {
  static const primary    = Color(0xFF3F7FB5);
  static const primaryLight = Color(0xFF8CB0BF);
  static const primarySoft  = Color(0xFFEBF3F9);
  static const primaryPale  = Color(0xFFEFF6FB);
  static const background = Color(0xFFF6F9FB);
  static const surface    = Color(0xFFFFFFFF);
  static const border     = Color(0xFFE5EAF0);
  static const error      = Color(0xFFEF4444);
  static const green      = Color(0xFF10B981);
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
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.all(AppRadii.lg),
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
            borderRadius: AppRadii.all(AppRadii.lg),
          ),
          textStyle: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w500),
        ),
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
        selectedItemColor: AppColors.primary,
        unselectedItemColor: const Color(0xFF9CA3AF),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: AppTypography.micro,
        unselectedLabelStyle: AppTypography.micro.copyWith(fontWeight: FontWeight.w400),
      ),
    );
  }
}

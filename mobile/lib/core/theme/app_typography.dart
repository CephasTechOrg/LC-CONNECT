import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's type scale.
///
/// Before this there was no scale at all: component themes hardcoded seven font sizes and every
/// screen called `GoogleFonts.dmSans(fontSize: N)` inline. A survey of `lib/` found these sizes in
/// use — 9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 14.5, 15, 15.5, 16, 17, 18, 19, 20,
/// 21, 22, 24, 25, 26 — and `Theme.of(context).textTheme` used in exactly zero feature files. A
/// type change therefore meant editing hundreds of call sites and missing some.
///
/// ## Why ten roles and not five
///
/// The half-steps above are ad-hoc tuning, not design intent, and they snap to their neighbours.
/// But the *integer* sizes cluster into ten genuinely distinct groups, each with a real job —
/// roughly 90 uses each at 13 and 14, 86 at 12, 47 at 11. Collapsing those into a fashionable
/// five-step scale would mean re-designing dense surfaces (the conversation list, attendance
/// countdowns, chat timestamps) rather than tokenising them, which is a different task.
///
/// Roles are named for what they *are*, not how big they are, so a future size change is one edit
/// here and nothing else.
class AppTypography {
  const AppTypography._();

  /// Every size the scale permits. A value not in here is a bug, not a decision — the guard test
  /// in `test/core/theme/` asserts the roles below stay on it.
  static const scale = <double>[10, 11, 12, 13, 14, 15, 16, 18, 20, 24];

  // ── headings ────────────────────────────────────────────────────────────────
  // Tighter line height: a heading wrapping to two lines should read as one block.

  /// Screen-defining figures and the largest titles. Rare by design.
  static TextStyle get display => _style(24, FontWeight.w700, height: 1.2);

  /// A screen's own title.
  static TextStyle get titleLarge => _style(20, FontWeight.w700, height: 1.25);

  /// A section or card title.
  static TextStyle get title => _style(18, FontWeight.w700, height: 1.3);

  /// A sub-section title, or a card title on a dense surface.
  static TextStyle get titleSmall => _style(16, FontWeight.w600, height: 1.35);

  // ── body ────────────────────────────────────────────────────────────────────
  // Roomier line height: running text needs it, and 1.45 keeps a 65-character measure readable.

  /// Emphasised body text — the first paragraph of a detail screen, a primary button.
  static TextStyle get bodyLarge => _style(15, FontWeight.w400, height: 1.45);

  /// Default body text.
  static TextStyle get body => _style(14, FontWeight.w400, height: 1.45);

  /// Dense body text — list subtitles, message previews.
  static TextStyle get bodySmall => _style(13, FontWeight.w400, height: 1.4);

  // ── utility ─────────────────────────────────────────────────────────────────
  // Heavier by default: these are small, so weight is what makes them legible rather than size.

  /// Chips, badges, and text inside a compact control.
  static TextStyle get label => _style(12, FontWeight.w600, height: 1.3);

  /// Timestamps and metadata.
  static TextStyle get caption => _style(11, FontWeight.w500, height: 1.3);

  /// The smallest permitted text: navigation labels, count badges. Nothing below 10.
  static TextStyle get micro => _style(10, FontWeight.w600, height: 1.2);

  static TextStyle _style(double size, FontWeight weight, {required double height}) =>
      GoogleFonts.dmSans(fontSize: size, fontWeight: weight, height: height);

  /// The roles above mapped onto Material's slots, so `Theme.of(context).textTheme` and a plain
  /// `Text` widget both land on the scale without the caller naming a style at all.
  ///
  /// Colour is applied by [AppTheme], not here: a role says how big and how heavy, never what
  /// colour — the same label is muted on one surface and inverted on another.
  static TextTheme get textTheme => TextTheme(
        displayLarge: display,
        displayMedium: display,
        displaySmall: display,
        headlineLarge: titleLarge,
        headlineMedium: titleLarge,
        headlineSmall: titleLarge,
        titleLarge: title,
        titleMedium: titleSmall,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: body,
        bodySmall: bodySmall,
        labelLarge: label,
        labelMedium: caption,
        labelSmall: micro,
      );
}

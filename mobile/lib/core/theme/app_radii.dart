import 'package:flutter/widgets.dart';

/// Corner radii, by the role of the thing being rounded.
///
/// A survey of `lib/` found fifteen different radii in use — 2, 4, 6, 7, 8, 9, 10, 11, 12, 13,
/// 14, 16, 18, 20, 24 — with the weight at 10 (72 uses), 12 (56), 14 (31), 16 (28) and 20 (28).
/// Those five are real and visually distinct; 6, 7, 9, 11, 13 and 18 are the same intentions
/// missed by a pixel or two.
///
/// Named by role rather than size for the same reason as the type scale: changing what a card
/// looks like should be one edit, not a search for `circular(14)` that also matches unrelated
/// widgets that happen to share the number.
class AppRadii {
  const AppRadii._();

  /// Indicator bars, progress tracks, the small grab handle on a sheet.
  static const hairline = 2.0;

  /// Tags and tiny inline chips.
  static const xs = 4.0;

  /// Compact controls — a segment, a small badge.
  static const sm = 8.0;

  /// The default for interactive surfaces: chips, list tiles, inline buttons.
  static const md = 10.0;

  /// Inputs and secondary panels.
  static const lg = 12.0;

  /// Cards — the app's most common container.
  static const card = 14.0;

  /// Large panels and feature cards.
  static const xl = 16.0;

  /// Bottom sheets and modals — the top corners only, as a rule.
  static const sheet = 20.0;

  /// Fully round: avatars, pills, circular buttons. Large rather than computed, so it does not
  /// need the widget's own height.
  static const full = 999.0;

  static BorderRadius all(double radius) => BorderRadius.circular(radius);

  /// A sheet's top corners. The bottom is flush with the screen edge.
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
}

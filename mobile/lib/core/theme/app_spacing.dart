import 'package:flutter/widgets.dart';

/// The app's spacing scale — a 4px grid.
///
/// Every gap, pad and inset comes from here. Before this there were no spacing constants at all,
/// which is how adjacent dashboard cards ended up with `fromLTRB(20, 4, 20, 8)` and
/// `fromLTRB(20, 12, 20, 4)` — two different rhythms, neither chosen.
///
/// A 4px grid rather than 8px: the app has genuinely dense surfaces (chat, the conversation list,
/// attendance rows) where 8px is too coarse a minimum step and half-steps would get invented
/// anyway, which is the problem this exists to stop.
class AppSpacing {
  const AppSpacing._();

  /// Hairline separation — between an icon and its label.
  static const xs = 4.0;

  /// Tight — inside a chip or badge.
  static const sm = 8.0;

  /// Default gap between related elements.
  static const md = 12.0;

  /// Gap between distinct elements in a group.
  static const lg = 16.0;

  /// Gap between sections.
  static const xl = 20.0;

  /// Generous separation — around a section heading, above a primary action.
  static const xxl = 24.0;

  /// Large vertical breathing room — empty states, the space below a screen's last section.
  static const xxxl = 32.0;

  /// The page gutter: horizontal inset from the screen edge to content.
  ///
  /// One value for the whole app, because inconsistent gutters are the most visible alignment
  /// error there is — content that shifts sideways as you move between screens.
  static const gutter = 20.0;

  /// Standard horizontal page padding. Vertical padding is the screen's own decision.
  static const pagePadding = EdgeInsets.symmetric(horizontal: gutter);

  /// Inner padding for a card or panel.
  static const cardPadding = EdgeInsets.all(lg);
}

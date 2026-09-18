import 'package:flutter/widgets.dart';

/// The app's elevation vocabulary.
///
/// There were twelve `BoxShadow` literals across `lib/`, one of them a private constant in a
/// single dashboard file, and no two agreeing on blur or alpha. They fell into three families,
/// which is what these are.
///
/// Elevation is information: it says "this sits above that". Spending it on everything flattens
/// the hierarchy, which is why there are three of these and not a numbered ramp of eight.
class AppShadows {
  const AppShadows._();

  /// A card at rest — barely there. The most common shadow in the app, and the right default:
  /// enough to separate a card from the background, not enough to read as floating.
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0A111827), blurRadius: 3, offset: Offset(0, 1)),
  ];

  /// Something genuinely above the page: a sheet, a menu, a floating action.
  static const raised = <BoxShadow>[
    BoxShadow(color: Color(0x14111827), blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// A tinted glow under a saturated surface — the spotlight carousel, a primary button.
  ///
  /// Takes the colour it sits under, because a neutral grey shadow beneath a coloured card reads
  /// as dirt rather than depth.
  static List<BoxShadow> tinted(Color color) => [
        BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 6)),
      ];
}

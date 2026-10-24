import 'package:flutter/material.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';

/// The app's standard surface card: white, borderless, floating on a soft shadow, optional tap.
///
/// The Material + InkWell + bordered Container recipe was hand-rolled on every Home card, each
/// with its own padding (10, 12, 14) and radius (14 as a literal, `AppRadii.card`, 20). One widget
/// means one look — the ripple is clipped to the same corners as the card, always.
///
/// Depth comes from [AppShadows.soft] rather than an outline: a hairline border on every card was
/// the main source of visual noise on Home.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// Only for tinted cards that need an edge to hold their colour (the urgent alert). Plain white
  /// cards stay borderless.
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.color = AppColors.surface,
    this.borderColor,
  });

  static final _radius = AppRadii.all(AppRadii.sheet);

  @override
  Widget build(BuildContext context) {
    final edge = borderColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: _radius,
        border: edge == null ? null : Border.all(color: edge),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: _radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A tinted square holding an icon — the leading element of a card row.
///
/// Home had six of these at six sizes (28, 38, 40, 42, 54, 56). Rows that sit next to each other
/// now share [size], so their text starts on the same vertical line.
class AppIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  const AppIconTile({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.background = AppColors.primarySoft,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.all(AppRadii.lg),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

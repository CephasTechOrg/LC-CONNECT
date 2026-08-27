import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';

/// Minimum touch target per Material / WCAG (48 logical pixels).
const double kMinTouchTarget = 48;

/// Icon button with tooltip, semantics, and a 48dp hit area.
class AppAccessibleIconButton extends StatelessWidget {
  const AppAccessibleIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.semanticsLabel,
    this.onPressed,
  });

  final String tooltip;
  final String? semanticsLabel;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel ?? tooltip,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          constraints: const BoxConstraints(
            minWidth: kMinTouchTarget,
            minHeight: kMinTouchTarget,
          ),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: icon,
        ),
      ),
    );
  }
}

/// Text action with a 48dp minimum touch height (section "See all" links, etc.).
class AppAccessibleTextAction extends StatelessWidget {
  const AppAccessibleTextAction({
    super.key,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final String? semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

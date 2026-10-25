import 'package:flutter/material.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// How every auth screen past the login opens: an icon tile, the page's title, one muted line —
/// centred as one block above the form, so the screen has a clear focal point instead of an icon
/// hanging in the top-left corner.
///
/// Register led with the app name instead of its own title, forgot-password's icon box stretched
/// into a full-width strip, and verify-email centred everything at its own sizes — three openings
/// for one flow.
class AuthHeading extends StatelessWidget {
  final IconData icon;
  final String title;

  /// The muted line. Spans so a screen can set a value in it apart, like the address a code was
  /// sent to.
  final List<InlineSpan> subtitle;

  const AuthHeading({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: AppRadii.all(AppRadii.card),
          ),
          child: Icon(icon, size: 30, color: AppColors.primaryText),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.display.copyWith(color: AppColors.textDark),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Narrower than the form so a centred paragraph keeps short, even lines.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text.rich(
            TextSpan(children: subtitle),
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textMuted, height: 1.5),
          ),
        ),
      ],
    );
  }
}

/// The value inside an [AuthHeading] subtitle — dark and bold against the muted line.
TextSpan authEmphasis(String text) => TextSpan(
      text: text,
      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark),
    );

/// A secondary choice under the primary button ("I already have a code", "Back to sign in"),
/// on a full 48dp target — these were bare text, a 20dp-tall tap.
class AuthTextLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  /// Muted for the way back; brand blue for a way forward.
  final bool muted;

  const AuthTextLink({super.key, required this.label, required this.onTap, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: muted ? AppColors.textMuted : AppColors.primaryText,
        ),
        child: Text(label, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

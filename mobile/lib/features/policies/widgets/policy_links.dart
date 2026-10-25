import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../data/policy_slugs.dart';

/// A tappable policy name for use inside a sentence.
///
/// Returns a [TextSpan] rather than a widget so the links sit in the same paragraph as the words
/// around them. A `Row` of buttons would break the sentence the user is being asked to agree to,
/// and the sentence is the part that has to read naturally.
TextSpan policyLinkSpan(
  BuildContext context, {
  required String slug,
  required String label,
}) {
  return TextSpan(
    text: label,
    style: AppTypography.bodySmall.copyWith(
      height: 1.45,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryText,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primaryText,
    ),
    // Pushed, so the reader returns the user to the form with everything still typed in.
    recognizer: TapGestureRecognizer()..onTap = () => context.push('/policies/$slug'),
  );
}

/// "Terms of Service and Privacy Policy" — the pair, linked, for use mid-sentence.
List<InlineSpan> policyPairSpans(BuildContext context, {TextStyle? plainStyle}) {
  final plain = plainStyle ??
      AppTypography.bodySmall.copyWith(height: 1.45, color: AppColors.textMid);
  return [
    policyLinkSpan(context, slug: PolicySlug.terms, label: 'Terms of Service'),
    TextSpan(text: ' and ', style: plain),
    policyLinkSpan(context, slug: PolicySlug.privacy, label: 'Privacy Policy'),
  ];
}

/// The three documents as one grouped card — the same soft card and inset hairlines as the
/// notification days and group settings.
class PolicyLinkList extends StatelessWidget {
  const PolicyLinkList({super.key});

  static const _entries = <(String, String, IconData)>[
    (PolicySlug.terms, 'Terms of Service', Icons.description_outlined),
    (PolicySlug.privacy, 'Privacy Policy', Icons.shield_outlined),
    (PolicySlug.guidelines, 'Community Guidelines', Icons.handshake_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (index, (slug, label, icon)) in _entries.indexed) ...[
            if (index > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.border,
                indent: AppSpacing.lg + 18 + AppSpacing.md,
              ),
            InkWell(
              onTap: () => context.push('/policies/$slug'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: AppColors.primaryText),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          label,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

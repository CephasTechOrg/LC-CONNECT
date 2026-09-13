import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
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
    style: GoogleFonts.dmSans(
      fontSize: 13,
      height: 1.45,
      fontWeight: FontWeight.w700,
      color: AppColors.primary,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primary,
    ),
    // Pushed, so the reader returns the user to the form with everything still typed in.
    recognizer: TapGestureRecognizer()..onTap = () => context.push('/policies/$slug'),
  );
}

/// "Terms of Service and Privacy Policy" — the pair, linked, for use mid-sentence.
List<InlineSpan> policyPairSpans(BuildContext context, {TextStyle? plainStyle}) {
  final plain = plainStyle ??
      GoogleFonts.dmSans(fontSize: 13, height: 1.45, color: AppColors.textMid);
  return [
    policyLinkSpan(context, slug: PolicySlug.terms, label: 'Terms of Service'),
    TextSpan(text: ' and ', style: plain),
    policyLinkSpan(context, slug: PolicySlug.privacy, label: 'Privacy Policy'),
  ];
}

/// The three documents as one grouped card.
///
/// Boxed with hairline dividers so it reads as a single set alongside the gate's reassurance
/// panel — three bare `ListTile`s under a bordered box looked like two unrelated components.
class PolicyLinkList extends StatelessWidget {
  const PolicyLinkList({super.key});

  static const _entries = <(String, String, IconData)>[
    (PolicySlug.terms, 'Terms of Service', Icons.description_outlined),
    (PolicySlug.privacy, 'Privacy Policy', Icons.shield_outlined),
    (PolicySlug.guidelines, 'Community Guidelines', Icons.handshake_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (final (index, (slug, label, icon)) in _entries.indexed) ...[
            if (index > 0)
              const Divider(height: 1, thickness: 1, color: AppColors.border, indent: 46),
            InkWell(
              onTap: () => context.push('/policies/$slug'),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(index == 0 ? 11 : 0),
                bottom: Radius.circular(index == _entries.length - 1 ? 11 : 0),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.dmSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

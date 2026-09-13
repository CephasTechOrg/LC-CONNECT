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

/// Stacked links for a settings screen or a footer, where there is no surrounding sentence.
class PolicyLinkList extends StatelessWidget {
  const PolicyLinkList({super.key});

  static const _entries = <String, String>{
    PolicySlug.terms: 'Terms of Service',
    PolicySlug.privacy: 'Privacy Policy',
    PolicySlug.guidelines: 'Community Guidelines',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in _entries.entries)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(
              entry.value,
              style: GoogleFonts.dmSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textDark,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textMuted),
            onTap: () => context.push('/policies/${entry.key}'),
          ),
      ],
    );
  }
}

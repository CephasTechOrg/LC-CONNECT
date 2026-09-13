part of '../screens/register_screen.dart';

/// The single thing a user ticks before an account can be created.
///
/// One checkbox carries **both** attestations: the policies, and that the two addresses above are
/// theirs. Splitting them into three boxes would get tapped through without reading, and the
/// campus-address attestation is the one that matters most — the app cannot verify it (the code
/// goes to the personal inbox), so the user saying so is the whole control.
///
/// The links are [TextSpan]s inside the sentence rather than buttons beside it, so the sentence
/// the user is agreeing to still reads as a sentence.
///
/// The label is deliberately **not** wrapped in a tap-to-toggle gesture. With link recognizers
/// inside the same text, an outer gesture competes in the same arena: reaching for "Privacy
/// Policy" could both open the document and silently tick the box. The checkbox's own 48px target
/// is the toggle; the text is for reading and for its links.
class _PolicyConsentCheckbox extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool> onChanged;

  const _PolicyConsentCheckbox({required this.accepted, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final plain = GoogleFonts.dmSans(
      fontSize: 13,
      height: 1.45,
      color: AppColors.textMid,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: Checkbox(
            value: accepted,
            onChanged: (value) => onChanged(value ?? false),
            activeColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            side: const BorderSide(color: AppColors.border, width: 1.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: RichText(
              text: TextSpan(
                style: plain,
                children: [
                  const TextSpan(text: 'I agree to the '),
                  ...policyPairSpans(context, plainStyle: plain),
                  const TextSpan(
                    text: ', and I confirm that the email addresses above are mine.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

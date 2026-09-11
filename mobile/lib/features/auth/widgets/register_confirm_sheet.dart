part of '../screens/register_screen.dart';

/// Last look at both addresses before anything is sent to Supabase.
///
/// The campus address is the typo nobody catches on their own: the confirmation code goes to the
/// *personal* inbox either way, so a mistyped campus email still verifies, still signs in, and
/// silently creates the account under an address that isn't theirs. Worse, `bootstrap_user` keys
/// the `User` row on it — so when the real owner of that address signs up later they collide with
/// a 409. A personal-email typo, by contrast, announces itself immediately (no code arrives).
///
/// Deliberately a review step rather than a second "confirm email" field: a repeated field invites
/// paste-the-same-value, which catches nothing.
///
/// Returns true only when the user explicitly confirms; null/false for dismiss, back, or Edit.
Future<bool?> _showRegisterConfirmSheet(
  BuildContext context, {
  required String campusEmail,
  required String contactEmail,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true, // lets the sheet grow past half-height at large text scales
    builder: (context) => _RegisterConfirmSheet(
      campusEmail: campusEmail,
      contactEmail: contactEmail,
    ),
  );
}

class _RegisterConfirmSheet extends StatelessWidget {
  final String campusEmail;
  final String contactEmail;

  const _RegisterConfirmSheet({
    required this.campusEmail,
    required this.contactEmail,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Cap at most of the viewport and scroll inside, so this stays usable on a short phone
      // and at the 1.4 text scale the app clamps to.
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + media.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Check your details',
                style: GoogleFonts.dmSans(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A typo in your campus email is easy to miss. Your code still arrives, but '
                'the account is created under the wrong address.',
                style: GoogleFonts.dmSans(
                  fontSize: 13.5,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              _ConfirmRow(
                label: "You'll sign in with",
                email: campusEmail,
                icon: Icons.school_outlined,
                emphasized: true,
              ),
              const SizedBox(height: 10),
              _ConfirmRow(
                label: 'Your code will be sent to',
                email: contactEmail,
                icon: Icons.mail_outline_rounded,
                emphasized: false,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textDark,
                        side: const BorderSide(color: AppColors.border, width: 1.5),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Edit',
                        style: GoogleFonts.dmSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _ActionButton(
                      label: 'Create account',
                      isLoading: false,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labelled address. The campus row is emphasized because it is the one being verified here.
class _ConfirmRow extends StatelessWidget {
  final String label;
  final String email;
  final IconData icon;
  final bool emphasized;

  const _ConfirmRow({
    required this.label,
    required this.email,
    required this.icon,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: emphasized ? AppColors.primarySoft : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasized ? AppColors.primary : AppColors.border,
          width: emphasized ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: emphasized ? AppColors.primary : AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                // Long addresses wrap rather than clip — never hide the thing being checked.
                Text(
                  email,
                  softWrap: true,
                  style: GoogleFonts.dmSans(
                    fontSize: 14.5,
                    fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textDark,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

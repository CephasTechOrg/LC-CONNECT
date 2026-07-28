part of '../screens/public_profile_screen.dart';

/// Staff contact block on a public profile — email (tap to mail), office, availability. Only the
/// fields that are set are shown. A student sees everything they need to decide to reach out.
class _StaffContactSection extends StatelessWidget {
  final PublicProfile profile;
  const _StaffContactSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    final email = profile.contactEmail;
    final rows = <Widget>[
      if (email != null && email.isNotEmpty)
        _ContactRow(
          icon: Icons.email_outlined,
          label: 'Email',
          value: email,
          onTap: () => launchUrl(Uri(scheme: 'mailto', path: email)),
        ),
      if (profile.positionOffice != null && profile.positionOffice!.isNotEmpty)
        _ContactRow(icon: Icons.meeting_room_outlined, label: 'Office', value: profile.positionOffice!),
      if (profile.positionAvailability != null && profile.positionAvailability!.isNotEmpty)
        _ContactRow(icon: Icons.schedule_outlined, label: 'Availability', value: profile.positionAvailability!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _ContactRow({required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: tappable ? AppColors.primary : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          if (tappable) const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// Bottom bar for a staff profile — a single Message action (students can message staff directly).
class _StaffMessageBar extends StatelessWidget {
  final bool loading;
  final VoidCallback onMessage;
  const _StaffMessageBar({required this.loading, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: loading ? null : onMessage,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.chat_bubble_outline_rounded, size: 18),
          label: Text(
            'Message',
            style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
      ),
    );
  }
}

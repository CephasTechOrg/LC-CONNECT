part of '../screens/profile_screen.dart';

class _PendingPositionBanner extends StatelessWidget {
  final String? title;
  final String status;
  const _PendingPositionBanner({this.title, required this.status});

  @override
  Widget build(BuildContext context) {
    final needsResubmit = status == 'rejected' || status == 'revoked';
    final color = needsResubmit ? AppColors.error : AppColors.primary;
    final bg = needsResubmit ? AppColors.error.withValues(alpha: 0.08) : AppColors.primarySoft;
    final message = switch (status) {
      'rejected' =>
        'Your campus position was not approved. Update your details and resubmit.',
      'revoked' =>
        'Your directory listing was revoked. Update your details and resubmit for review.',
      _ =>
        title != null && title!.isNotEmpty
            ? '$title is pending verification. You can use LC Connect, but you will not appear in the campus directory until approved.'
            : 'Your campus position is pending verification. You can use LC Connect, but you will not appear in the campus directory until approved.',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: needsResubmit ? () => context.push('/profile/campus-position') : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  needsResubmit ? Icons.info_outline_rounded : Icons.hourglass_top_rounded,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: GoogleFonts.dmSans(
                          fontSize: 12.5,
                          color: AppColors.textMid,
                          height: 1.35,
                        ),
                      ),
                      if (needsResubmit) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Tap to update and resubmit',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (needsResubmit)
                  Icon(Icons.chevron_right_rounded, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

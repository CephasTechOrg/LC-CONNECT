part of '../screens/home_screen.dart';

class _RecentMatchCard extends StatelessWidget {
  final MessageThread thread;
  final VoidCallback onTap;
  const _RecentMatchCard({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Kind-agnostic: works for a DM (partner) or a group (title/avatar) — the unified inbox
    // feeds either kind here, so never force-unwrap the partner.
    final latest = thread.latestMessage;
    final previewText =
        latest?.body ?? (thread.isGroup ? 'No messages yet' : 'New match — say hello!');
    final timeText = latest != null ? _timeAgo(latest.createdAt) : '';
    final unread = !thread.isGroup && latest != null && latest.readAt == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D111827),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  AvatarWidget(imageUrl: thread.avatarUrl, size: 44),
                  if (unread)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textMid),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (timeText.isNotEmpty)
                    Text(
                      timeText,
                      style: GoogleFonts.dmSans(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                  if (unread) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoMatchesYet extends StatelessWidget {
  const _NoMatchesYet();

  @override
  Widget build(BuildContext context) {
    return AppEmptyStateCard(
      icon: Icons.people_outline_rounded,
      title: 'No messages yet',
      subtitle: 'Accept a connection request or find study partners.',
      actionLabel: 'Find Study Partners',
      onAction: () => context.go('/discover?tab=study'),
    );
  }
}

part of '../screens/chat_screen.dart';

// ── Chat header ───────────────────────────────────────────────────
// Compact, identity-first: back • avatar • name • action. Tapping the avatar/name opens the
// partner's profile (DM) or the group's info screen (group); no separate identity card below.
class _ChatHeader extends StatelessWidget {
  final String title;
  final String? avatarUrl;
  final bool isGroup;

  /// Tap the avatar/name → the partner's profile (DM) or the group detail screen (group).
  final VoidCallback? onIdentityTap;

  /// DM only: the ⋯ menu (report / block the partner).
  final VoidCallback? onMenu;

  const _ChatHeader({
    this.title = 'Messages',
    this.avatarUrl,
    this.isGroup = false,
    this.onIdentityTap,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textDark),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: InkWell(
              onTap: onIdentityTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    _HeaderAvatar(url: avatarUrl, isGroup: isGroup),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isGroup)
            IconButton(
              icon: const Icon(Icons.info_outline_rounded, size: 21, color: AppColors.textMuted),
              onPressed: onIdentityTap,
            )
          else if (onMenu != null)
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, size: 22, color: AppColors.textMuted),
              onPressed: onMenu,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// The header avatar — the partner's photo (DM) or the group's photo, each with the right
/// fallback icon (person vs group) instead of a generic placeholder.
class _HeaderAvatar extends StatelessWidget {
  final String? url;
  final bool isGroup;
  const _HeaderAvatar({this.url, this.isGroup = false});

  @override
  Widget build(BuildContext context) {
    if (!isGroup) return AvatarWidget(imageUrl: url, size: 38);
    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
      child: url != null
          ? Image.network(url!, width: 38, height: 38, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.groups_outlined, size: 20, color: AppColors.primary))
          : const Icon(Icons.groups_outlined, size: 20, color: AppColors.primary),
    );
  }
}

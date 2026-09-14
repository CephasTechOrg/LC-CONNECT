part of '../screens/connections_screen.dart';

class _OutgoingCard extends ConsumerWidget {
  final ConnectionRequest request;
  const _OutgoingCard({required this.request});

  /// Confirmed because it cannot be undone from here — withdrawing deletes the request, and
  /// asking again means finding the person and starting over.
  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final name = request.partnerProfile?.displayName ?? 'this person';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Withdraw request?',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
        content: Text(
          "$name will no longer see your request. You can send another one later.",
          style: GoogleFonts.dmSans(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep it', style: GoogleFonts.dmSans()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Withdraw',
                style: GoogleFonts.dmSans(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(connectionsNotifierProvider.notifier).withdraw(request.id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          apiErrorMessage(error, fallback: "Couldn't withdraw that. Please try again."),
          style: GoogleFonts.dmSans(),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final p = r.partnerProfile;

    return GestureDetector(
      onTap: p != null
          ? () => context.push('/users/${p.profileId}', extra: p.displayName)
          : null,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          _Avatar(avatarUrl: p?.avatarUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        p?.displayName ?? 'LC Student',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    if (p?.campusVerified ?? false) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: 14),
                    ],
                  ],
                ),
                if (p?.major != null)
                  Text(
                    p!.major!,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                const SizedBox(height: 6),
                if (r.intent != null) _IntentBadge(intent: r.intent!),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _timeAgo(r.createdAt),
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Pending',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              TextButton(
                onPressed: () => _withdraw(context, ref),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.textMuted,
                ),
                child: Text('Withdraw',
                    style: GoogleFonts.dmSans(
                        fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────

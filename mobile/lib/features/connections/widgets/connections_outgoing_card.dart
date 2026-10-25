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
        title: const Text('Withdraw request?'),
        content: Text(
          "$name will no longer see your request. You can send another one later.",
          style: AppTypography.body.copyWith(color: AppColors.textMid, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Withdraw',
              // Darker than [AppColors.error], which is ~3.8:1 on white.
              style: AppTypography.body.copyWith(
                color: AppColors.errorText,
                fontWeight: FontWeight.w700,
              ),
            ),
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
    final intent = _intentLabel(r.intent);

    // No "Pending" chip: everything on this tab is pending — that is what the tab is. What
    // varies is the age, so that is what the card shows, as "Sent 2d ago".
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PersonRow(
            profile: p,
            meta: p?.major ?? '',
            trailing: _ActionButton(
              label: 'Withdraw',
              loading: false,
              filled: false,
              onTap: () => _withdraw(context, ref),
            ),
          ),
          Padding(
            // Under the name, not under the avatar: 48 avatar + 12 gap. Its own line so a long
            // major cannot push the age off the end.
            padding: const EdgeInsets.only(left: 60),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (intent != null) _IntentChip(intent: r.intent!, label: intent),
                Text(
                  _sentAgo(r.createdAt),
                  style: AppTypography.label.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _sentAgo(DateTime at) {
  final age = _timeAgo(at);
  return 'Sent ${age == 'Just now' ? 'just now' : age}';
}

// ── Shared widgets ────────────────────────────────────────────────

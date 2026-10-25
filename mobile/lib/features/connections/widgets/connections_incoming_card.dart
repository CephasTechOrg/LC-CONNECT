part of '../screens/connections_screen.dart';

class _IncomingCard extends ConsumerStatefulWidget {
  final ConnectionRequest request;
  const _IncomingCard({required this.request});

  @override
  ConsumerState<_IncomingCard> createState() => _IncomingCardState();
}

class _IncomingCardState extends ConsumerState<_IncomingCard> {
  bool _accepting = false;
  bool _declining = false;

  Future<void> _accept() async {
    if (_accepting || _declining) return;
    setState(() => _accepting = true);
    try {
      await ref
          .read(connectionsNotifierProvider.notifier)
          .accept(widget.request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "You're now connected with ${widget.request.partnerProfile?.displayName ?? 'them'}",
            ),
            backgroundColor: _successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            apiErrorMessage(e, fallback: 'Could not accept — try again.'),
          ),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _decline() async {
    if (_accepting || _declining) return;
    setState(() => _declining = true);
    try {
      await ref
          .read(connectionsNotifierProvider.notifier)
          .decline(widget.request.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            apiErrorMessage(e, fallback: 'Could not decline — try again.'),
          ),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _declining = false);
    }
  }

  /// AA for white text; the brand [AppColors.green] is ~2.5:1 under a white label.
  static const _successGreen = AppColors.green;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final p = r.partnerProfile;
    final intent = _intentLabel(r.intent);
    final note = r.note?.trim() ?? '';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PersonRow(profile: p, meta: _metaLine(p, _timeAgo(r.createdAt))),
          if (intent != null) ...[
            const SizedBox(height: AppSpacing.md),
            _IntentChip(intent: r.intent!, label: intent),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            // A quiet block, not a bordered italic box: the note is the sender's own words, so
            // it reads as a message rather than as another piece of card chrome.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppRadii.all(AppRadii.lg),
              ),
              child: Text(
                '"$note"',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMid,
                  height: 1.45,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Decline',
                  loading: _declining,
                  filled: false,
                  onTap: _decline,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionButton(
                  label: 'Accept',
                  loading: _accepting,
                  filled: true,
                  onTap: _accept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Outgoing request card ─────────────────────────────────────────

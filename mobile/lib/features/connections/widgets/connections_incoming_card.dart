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
              '🎉 You matched with ${widget.request.partnerProfile?.displayName ?? 'them'}!',
            ),
            backgroundColor: AppColors.green,
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

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final p = r.partnerProfile;

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name row
          GestureDetector(
            onTap: p != null
                ? () => context.push(
                      '/users/${p.profileId}',
                      extra: p.displayName,
                    )
                : null,
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
                        if (p?.isVerified ?? false) ...[
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
                  ],
                ),
              ),
              Text(
                _timeAgo(r.createdAt),
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppColors.textMuted),
              ),
            ],
            ),
          ),
          // Intent badge
          if (r.intent != null) ...[
            const SizedBox(height: 10),
            _IntentBadge(intent: r.intent!),
          ],
          // Note
          if (r.note != null && r.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '"${r.note}"',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: AppColors.textMid,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Accept / Decline buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Decline',
                  loading: _declining,
                  outlined: true,
                  onTap: _decline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: 'Accept',
                  loading: _accepting,
                  outlined: false,
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

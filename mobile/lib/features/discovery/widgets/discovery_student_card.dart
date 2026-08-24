part of '../screens/discovery_screen.dart';

// ══════════════════════════════════════════════════════════════════
// Student card
// ══════════════════════════════════════════════════════════════════

class _StudentCard extends StatefulWidget {
  final DiscoveryCard card;
  final Future<void> Function() onConnect;
  final Future<void> Function() onStudyTogether;
  final VoidCallback onSkip;
  final VoidCallback onMore;

  const _StudentCard({
    super.key,
    required this.card,
    required this.onConnect,
    required this.onStudyTogether,
    required this.onSkip,
    required this.onMore,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool _isActing = false;

  Future<void> _act(Future<void> Function() action) async {
    if (_isActing) return;
    setState(() => _isActing = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage(e, fallback: 'Something went wrong. Please try again.'),
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final primaryCode =
        c.lookingForCodes.isNotEmpty ? c.lookingForCodes[0] : null;
    final primaryLabel =
        c.lookingFor.isNotEmpty ? c.lookingFor[0] : null;
    final matchReason =
        c.matchReasons.isNotEmpty ? c.matchReasons[0] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: looking-for badge + menu ───────────────────
            Row(
              children: [
                if (primaryCode != null && primaryLabel != null)
                  _LookingForBadge(code: primaryCode, label: primaryLabel),
                const Spacer(),
                IconButton(
                  onPressed: widget.onMore,
                  icon: const Icon(Icons.more_horiz,
                      color: AppColors.textMuted, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Profile row: avatar + info ──────────────────────────
            GestureDetector(
              onTap: () => context.push(
                '/users/${c.profileId}',
                extra: c.displayName,
              ),
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(avatarUrl: c.avatarUrl),
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
                              c.displayName ?? 'Student',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.dmSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          if (c.isVerified) ...[
                            const SizedBox(width: 5),
                            const VerifiedBadge(size: 16),
                          ],
                        ],
                      ),
                      if (c.classYear != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          'Class of ${c.classYear}',
                          style: GoogleFonts.dmSans(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                      if (c.major != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          c.major!,
                          style: GoogleFonts.dmSans(
                              fontSize: 13, color: AppColors.textMuted),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.location_city_outlined,
                              size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            'Livingstone College',
                            style: GoogleFonts.dmSans(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              ),
            ),

            // ── Interests ──────────────────────────────────────────
            if (c.interests.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InterestChips(interests: c.interests),
            ],

            // ── Languages ─────────────────────────────────────────
            if (c.languagesSpoken.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.language_outlined,
                      size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Speaks ${c.languagesSpoken.join(', ')}',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],

            // ── Additional looking-for chips ───────────────────────
            if (c.lookingFor.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: c.lookingFor.skip(1).map((label) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPale,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primaryLight.withAlpha(80)),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.dmSans(
                          fontSize: 11.5,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),
            ],

            // ── Match reason ───────────────────────────────────────
            if (matchReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_outline,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        matchReason,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Action buttons ────────────────────────────────────
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Connect',
                    icon: Icons.person_add_outlined,
                    isLoading: _isActing,
                    onTap: () => _act(widget.onConnect),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'Study Together',
                    icon: Icons.menu_book_outlined,
                    isLoading: _isActing,
                    onTap: () => _act(widget.onStudyTogether),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Maybe Later ───────────────────────────────────────
            Center(
              child: TextButton(
                onPressed: _isActing ? null : widget.onSkip,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Maybe Later',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar ─────────────────────────────────────────────────────────

part of '../screens/discovery_screen.dart';

// ══════════════════════════════════════════════════════════════════
// Student card — compact list preview; full detail on profile tap
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
            apiErrorMessage(
              e,
              fallback: 'Something went wrong. Please try again.',
            ),
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final showStudyTogether = c.lookingForCodes.contains('study_partner');
    final lookingCodes = c.lookingForCodes;
    final lookingLabels = c.lookingFor;
    // Cap at two on the list card; the rest live on the public profile.
    final lookingPairs = <(String, String)>[
      for (
        var i = 0;
        i < lookingCodes.length && i < lookingLabels.length && i < 2;
        i++
      )
        (lookingCodes[i], lookingLabels[i]),
    ];
    final matchReason = c.matchReasons.isNotEmpty ? c.matchReasons[0] : null;

    return Semantics(
      label: c.displayName ?? 'Student profile',
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push(
                        '/users/${c.profileId}',
                        extra: c.displayName,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Avatar(avatarUrl: c.avatarUrl),
                          const SizedBox(width: 10),
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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textDark,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    if (c.campusVerified) ...[
                                      const SizedBox(width: 4),
                                      const VerifiedBadge(size: 14),
                                    ],
                                  ],
                                ),
                                if (c.classYear != null || c.major != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (c.classYear != null)
                                        'Class of ${c.classYear}',
                                      if (c.major != null) c.major!,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onMore,
                    tooltip: 'More options',
                    icon: const Icon(
                      Icons.more_horiz,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: kMinTouchTarget,
                      minHeight: kMinTouchTarget,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              if (lookingPairs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final pair in lookingPairs)
                      _LookingForBadge(code: pair.$1, label: pair.$2),
                  ],
                ),
              ],

              // One brief line for interests + languages, not two stacked
              // rows: the full lists live on the public profile. Languages
              // lead when this student is here for language exchange — for
              // them it is the matching signal, not decoration.
              if (c.interests.isNotEmpty || c.languagesSpoken.isNotEmpty) ...[
                const SizedBox(height: 8),
                _InterestLanguageLine(
                  interests: c.interests,
                  languages: c.languagesSpoken,
                  prioritizeLanguage: lookingCodes.contains(
                    'language_exchange',
                  ),
                ),
              ],

              if (matchReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  matchReason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 10),
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
                  if (showStudyTogether) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        label: 'Study Together',
                        icon: Icons.menu_book_outlined,
                        isLoading: _isActing,
                        secondary: true,
                        onTap: () => _act(widget.onStudyTogether),
                      ),
                    ),
                  ],
                ],
              ),
              Center(
                child: TextButton(
                  onPressed: _isActing ? null : widget.onSkip,
                  style: TextButton.styleFrom(
                    // Visible and quiet — but a full-height target. It used
                    // to be 36dp tall, under the app's own 48dp minimum.
                    minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                  child: Text(
                    'Maybe Later',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

part of '../screens/discovery_screen.dart';

// ══════════════════════════════════════════════════════════════════
// Student card — compact list preview; full detail on profile tap
// ══════════════════════════════════════════════════════════════════

class _StudentCard extends StatefulWidget {
  final DiscoveryCard card;
  final Future<void> Function() onConnect;
  final VoidCallback onSkip;
  final VoidCallback onMore;

  const _StudentCard({
    super.key,
    required this.card,
    required this.onConnect,
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
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        // The shared card surface (borderless, soft shadow), same as Home and Activities.
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.all(AppRadii.sheet),
          boxShadow: AppShadows.soft,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
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
                          const SizedBox(width: AppSpacing.md),
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
                                        style: AppTypography.titleSmall.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textDark,
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
                                    style: AppTypography.caption.copyWith(
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
                const SizedBox(height: AppSpacing.sm),
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
                const SizedBox(height: AppSpacing.sm),
                _InterestLanguageLine(
                  interests: c.interests,
                  languages: c.languagesSpoken,
                  prioritizeLanguage: lookingCodes.contains(
                    'language_exchange',
                  ),
                ),
              ],

              if (matchReason != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.primaryText),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        matchReason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Row(
                  children: [
                    // "Maybe later" stays a visible, labelled choice — it just shares the
                    // action row instead of costing the card a 48dp row of its own.
                    TextButton(
                      onPressed: _isActing ? null : widget.onSkip,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                        foregroundColor: AppColors.textMuted,
                      ),
                      child: Text(
                        'Maybe later',
                        style: AppTypography.label.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _ActionButton(
                        label: 'Connect',
                        icon: Icons.person_add_outlined,
                        isLoading: _isActing,
                        onTap: () => _act(widget.onConnect),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

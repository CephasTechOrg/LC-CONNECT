import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../../programs/providers/programs_provider.dart';
import '../providers/scholars_provider.dart';

/// How the Blueprint Bond entry point presents itself.
enum BlueprintBondStyle {
  /// A call-to-action for the dashboard, shown **only** while the professional profile is still
  /// incomplete. Once there is nothing left to do it disappears entirely: a prompt that never goes
  /// away stops reading as a prompt and becomes clutter on a feed the student scrolls daily.
  ///
  /// It used to leave a quiet status row behind instead. That was deliberate — removing it
  /// entirely left a verified scholar with no way to see their status — but the answer to that is
  /// the permanent [entry] row on Profile, not a residue on the dashboard.
  prompt,

  /// A permanent, compact row. Lives on Profile, where the student expects to find their own
  /// things regardless of state, so it stays put whether complete or not. This is what makes it
  /// safe for [prompt] to vanish.
  entry,
}

/// Shown only to verified Presidential Scholars (per the Blueprint Bond spec). Renders nothing
/// for anyone else, so it's safe to drop into any screen unguarded.
class BlueprintBondCard extends ConsumerWidget {
  final BlueprintBondStyle style;

  const BlueprintBondCard({super.key, this.style = BlueprintBondStyle.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 0 keeps the rendering identical to before: hidden unless confirmed eligible. The
    // difference is that `unknown` is now *distinguishable* from `no`, which is what lets Phase 1
    // put a retry here instead of silence.
    if (!ref.watch(scholarEligibilityProvider).isPermitted) return const SizedBox.shrink();

    final profileAsync = ref.watch(scholarProfileNotifierProvider);
    // Keep the last known profile across reloads so the prompt doesn't shrink→grow (blink)
    // every time Campus Hub remounts and the notifier briefly looks empty.
    final profile = profileAsync.asData?.value ?? profileAsync.value;

    if (style == BlueprintBondStyle.prompt) {
      // First load only: stay silent until we know whether the profile is already complete.
      // Once something has rendered, remounts keep [profile] via asData and don't flicker.
      if (profile == null) return const SizedBox.shrink();
      // Done — the prompt retires. The permanent row on Profile is where status lives.
      if (profile.isComplete) return const SizedBox.shrink();
      return _PromptCard(
        onTap: () => context.push('/profile/blueprint-bond'),
      );
    }

    // Profile: permanent, but it must not *assert* a state it could not read. A failed
    // `/scholars/me` used to render "profile incomplete" with an amber dot for a scholar whose
    // profile may well be finished — worse than saying nothing.
    return _EntryRow(
      isComplete: profile?.isComplete,
      reviewStatus: profile?.reviewStatus,
      onTap: () => context.push('/profile/blueprint-bond'),
    );
  }
}

/// Campus Hub: one short line — open the editor for what’s still needed.
class _PromptCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PromptCard({required this.onTap});

  /// The Blueprint brand navy. Kept as the icon and text colour rather than the card fill — see
  /// [build] for why the card itself is no longer filled with it.
  static const _blueprintNavy = Color(0xFF1B3A5C);

  @override
  Widget build(BuildContext context) {
    // A light card, not the saturated navy this used to be.
    //
    // Report #18: on an Honors student's dashboard this sits directly above the attendance
    // card, and that card is a fully saturated `AppColors.primary` surface with white text. Two
    // adjacent dark blue cards, each shouting, and neither reading as more urgent than the
    // other — which is the same as neither being urgent.
    //
    // Emphasis follows urgency. Attendance is *time-bounded*: a session is open right now, with
    // a countdown, and missing it cannot be undone. The Blueprint prompt is a standing task with
    // no deadline. So the saturated treatment belongs to attendance, and this becomes a quiet
    // invitation — still branded by its navy icon and title, no longer competing for the same
    // signal. Copy stays a single line; field-level “still needed” detail lives in the editor.
    return Padding(
      // Top gap only, like every Home block above the sections: whether this card shows or
      // hides, the cards around it keep the same rhythm.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      // The same floating white card as every other Home row (AppCard), so the prompt reads as
      // part of the page rather than a strip wedged between two cards.
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            const AppIconTile(
              icon: Icons.workspace_premium_rounded,
              color: Colors.white,
              background: _blueprintNavy,
            ),
            const SizedBox(width: AppSpacing.md),
            // Always one line: on a narrow phone the title scales down a little rather than
            // wrapping and making the card twice as tall.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Finish your Blueprint Bond profile',
                  maxLines: 1,
                  style: AppTypography.titleSmall.copyWith(color: AppColors.textDark),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Profile: a quiet, permanent row that matches the surrounding sections rather than shouting
/// over them — the student already knows they're a scholar; this is just the way in.
class _EntryRow extends StatelessWidget {
  /// `null` when the profile could not be read — render neither "complete" nor "incomplete".
  final bool? isComplete;
  final String? reviewStatus;
  final VoidCallback onTap;
  const _EntryRow({required this.isComplete, this.reviewStatus, required this.onTap});

  (Color, String) get _status {
    if (isComplete == null) return (AppColors.textMuted, 'Blueprint Bond');
    if (isComplete == false) {
      return (const Color(0xFFD97706), 'Blueprint Bond · profile incomplete');
    }
    // Prefer review state once the profile itself is filled in.
    return switch (reviewStatus) {
      'approved' => (AppColors.green, 'Blueprint Bond · approved for partners'),
      'pending_review' => (AppColors.primary, 'Blueprint Bond · awaiting Honors review'),
      'changes_requested' => (const Color(0xFFD97706), 'Blueprint Bond · changes requested'),
      'revoked' => (AppColors.error, 'Blueprint Bond · visibility revoked'),
      _ => (AppColors.textMuted, 'Blueprint Bond · ready to submit'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusLabel) = _status;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B3A5C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Honors Student is an account status and leads; Blueprint Bond is what
                    // that status gives access to, so it reads as the detail underneath. This
                    // row only renders for verified scholars, so the label is always true.
                    Text(
                      'Honors Student',
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            statusLabel,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.label.copyWith(
                              fontWeight: FontWeight.w400,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

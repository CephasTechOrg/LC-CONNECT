import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
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
        missingFields: profile.missingFields,
        onTap: () => context.push('/profile/blueprint-bond'),
      );
    }

    // Profile: permanent, but it must not *assert* a state it could not read. A failed
    // `/scholars/me` used to render "profile incomplete" with an amber dot for a scholar whose
    // profile may well be finished — worse than saying nothing.
    return _EntryRow(
      isComplete: profile?.isComplete,
      onTap: () => context.push('/profile/blueprint-bond'),
    );
  }
}

/// Campus Hub: a single, focused nudge with one job — get the profile finished.
class _PromptCard extends StatelessWidget {
  final VoidCallback onTap;
  final List<String> missingFields;
  const _PromptCard({required this.onTap, this.missingFields = const []});

  /// Human wording for the API's field names. A generic "finish your profile" makes the student
  /// open the screen to discover what is left; naming the next step is the difference between a
  /// nudge and a chore.
  static const _labels = <String, String>{
    'summary': 'a short summary',
    'headshot': 'a headshot',
    'resume': 'your résumé',
    'skills': 'a few skills',
    'career_interests': 'career interests',
    'employer_visibility_consent': 'employer visibility',
  };

  String get _subtitle {
    final named = missingFields.map((f) => _labels[f]).whereType<String>().toList();
    if (named.isEmpty) return 'Get seen by employer partners';
    if (named.length == 1) return 'Still needed: ${named.first}';
    if (named.length == 2) return 'Still needed: ${named[0]} and ${named[1]}';
    return 'Still needed: ${named[0]}, ${named[1]} and ${named.length - 2} more';
  }

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
    // signal.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.xs,
      ),
      child: Material(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _blueprintNavy,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Finish your Blueprint Bond profile',
                        // 14.5 and 12.5 were off any scale; `bodyLarge` and `label` are the
                        // roles. Navy on the tinted surface measures 10.36:1 and the subtitle
                        // 9.19:1 — both well past AA, unlike white-on-navy which this replaces.
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _blueprintNavy,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.arrow_forward_rounded, color: _blueprintNavy, size: 18),
              ],
            ),
          ),
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
  final VoidCallback onTap;
  const _EntryRow({required this.isComplete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (isComplete) {
      true => AppColors.green,
      false => const Color(0xFFD97706),
      null => AppColors.textMuted,
    };
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
                      style: GoogleFonts.dmSans(
                        fontSize: 14.5,
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
                            switch (isComplete) {
                              true => 'Blueprint Bond · profile complete',
                              false => 'Blueprint Bond · profile incomplete',
                              null => 'Blueprint Bond',
                            },
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
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

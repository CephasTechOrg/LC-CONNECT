import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../programs/providers/programs_provider.dart';
import '../providers/scholars_provider.dart';

/// How the Blueprint Bond entry point presents itself.
enum BlueprintBondStyle {
  /// A call-to-action, shown only while the professional profile is still incomplete.
  /// Once there's nothing left to do it disappears — a prompt that never goes away stops
  /// reading as a prompt and just becomes clutter on a feed the student scrolls daily.
  prompt,

  /// A permanent, compact row. Lives on Profile, where the student expects to find their own
  /// things regardless of state, so it stays put whether complete or not.
  entry,
}

/// Shown only to verified Presidential Scholars (per the Blueprint Bond spec). Renders nothing
/// for anyone else, so it's safe to drop into any screen unguarded.
class BlueprintBondCard extends ConsumerWidget {
  final BlueprintBondStyle style;

  const BlueprintBondCard({super.key, this.style = BlueprintBondStyle.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isVerifiedScholarProvider)) return const SizedBox.shrink();

    final profileAsync = ref.watch(scholarProfileNotifierProvider);
    // Keep the last known profile across reloads so the prompt doesn't shrink→grow (blink)
    // every time Campus Hub remounts and the notifier briefly looks empty.
    final profile = profileAsync.asData?.value ?? profileAsync.value;

    final isComplete = profile != null &&
        (profile.summary?.isNotEmpty ?? false) &&
        (profile.hasResume || profile.hasHeadshot);

    if (style == BlueprintBondStyle.prompt) {
      // First load only: stay silent until we know whether the profile is already complete.
      // Once something has rendered, remounts keep [profile] via asData and don't flicker.
      if (profile == null) return const SizedBox.shrink();
      // Nothing left to nudge about, but the status still belongs on the dashboard. The card
      // used to vanish entirely here, so finishing the profile removed the only place a
      // verified scholar could see they were one — leaving the notification as the sole cue.
      if (isComplete) {
        return _StatusRow(onTap: () => context.push('/profile/blueprint-bond'));
      }
      return _PromptCard(onTap: () => context.push('/profile/blueprint-bond'));
    }

    return _EntryRow(
      isComplete: isComplete,
      onTap: () => context.push('/profile/blueprint-bond'),
    );
  }
}

/// Campus Hub, once there is nothing left to finish: a slim confirmation that the student is a
/// verified Honors Student, still linking through to Blueprint Bond. Deliberately much quieter
/// than [_PromptCard] — it is status, not a call to action, and it sits on a feed the student
/// scrolls every day.
class _StatusRow extends StatelessWidget {
  final VoidCallback onTap;
  const _StatusRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Material(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    size: 18, color: Color(0xFF1B3A5C)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Honors Student',
                    style: GoogleFonts.dmSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1B3A5C),
                    ),
                  ),
                ),
                Text(
                  'Blueprint Bond',
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Campus Hub: a single, focused nudge with one job — get the profile finished.
class _PromptCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PromptCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Material(
        color: const Color(0xFF1B3A5C),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
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
                        style: GoogleFonts.dmSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Get seen by employer partners',
                        style: GoogleFonts.dmSans(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.9), size: 18),
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
  final bool isComplete;
  final VoidCallback onTap;
  const _EntryRow({required this.isComplete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = isComplete ? AppColors.green : const Color(0xFFD97706);
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
                            isComplete
                                ? 'Blueprint Bond · profile complete'
                                : 'Blueprint Bond · profile incomplete',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../programs/providers/programs_provider.dart';
import '../providers/scholars_provider.dart';

/// Shown only to verified Presidential Scholars — in Profile and Campus Hub (per the Blueprint
/// Bond spec). Renders nothing for anyone else, so it's safe to drop into any screen unguarded.
class BlueprintBondCard extends ConsumerWidget {
  const BlueprintBondCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isScholar = ref.watch(isVerifiedScholarProvider);
    if (!isScholar) return const SizedBox.shrink();

    final scholarAsync = ref.watch(scholarProfileNotifierProvider);
    final profile = scholarAsync.value;
    final isComplete = profile != null &&
        (profile.summary?.isNotEmpty ?? false) &&
        (profile.hasResume || profile.hasHeadshot);
    final subtitle = isComplete
        ? 'View your professional profile'
        : 'Complete your professional profile for employer opportunities';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: const Color(0xFF1B3A5C),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => context.push('/profile/blueprint-bond'),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Blueprint Bond',
                        style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../data/group_models.dart';
import '../providers/groups_provider.dart';

/// A quick-access strip of the groups you're in, at the top of the Groups panel. Tapping one
/// opens its chat. Renders nothing until you've joined at least one group.
class YourGroupsSection extends ConsumerStatefulWidget {
  const YourGroupsSection({super.key});

  @override
  ConsumerState<YourGroupsSection> createState() => _YourGroupsSectionState();
}

class _YourGroupsSectionState extends ConsumerState<YourGroupsSection> {
  bool _opening = false;

  Future<void> _open(GroupSummary group) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      // GroupSummary lacks conversation_id; fetch the full group for it.
      final full = await ref.read(groupsRepositoryProvider).get(group.id);
      if (!mounted) return;
      context.push(
        '/messages/group/${full.conversationId}',
        extra: GroupChatArgs(name: full.name, groupId: full.id),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open the group', style: GoogleFonts.dmSans(color: Colors.white)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(myGroupsProvider).asData?.value ?? const <GroupSummary>[];
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            'Your Groups',
            style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
        ),
        SizedBox(
          height: 94,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _GroupBubble(group: groups[i], onTap: () => _open(groups[i])),
          ),
        ),
      ],
    );
  }
}

class _GroupBubble extends StatelessWidget {
  final GroupSummary group;
  final VoidCallback onTap;
  const _GroupBubble({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: group.avatarUrl != null
                  ? Image.network(group.avatarUrl!, width: 54, height: 54, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.groups_outlined, size: 24, color: AppColors.primary))
                  : const Icon(Icons.groups_outlined, size: 24, color: AppColors.primary),
            ),
            const SizedBox(height: 6),
            Text(
              group.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMid, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../data/placeholder_groups.dart';

/// Campus Groups panel matching the Connect mockup. Actions are local-only.
class GroupsPanel extends StatefulWidget {
  const GroupsPanel({super.key});

  @override
  State<GroupsPanel> createState() => _GroupsPanelState();
}

class _GroupsPanelState extends State<GroupsPanel> {
  String _category = 'All';
  late Map<String, String> _states;

  @override
  void initState() {
    super.initState();
    _states = {
      for (final g in placeholderGroups) g.name: g.action,
    };
  }

  void _toggle(String name) {
    setState(() {
      final cur = _states[name] ?? 'Join';
      _states[name] = switch (cur) {
        'Join' => 'Joined',
        'Joined' => 'Join',
        'Request' => 'Pending',
        'Pending' => 'Request',
        _ => cur,
      };
    });
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Groups will be available soon.',
          style: GoogleFonts.dmSans(),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = placeholderGroups
        .where((g) => _category == 'All' || g.category == _category)
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        AppFilterChipRow(
          labels: groupCategories,
          selected: _category,
          onSelect: (c) => setState(() => _category = c),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _FeaturedGroupCard(
            state: _states['Pre-Health Society'] ?? 'Join',
            onAction: () => _toggle('Pre-Health Society'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            children: [
              Text(
                'All Groups',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _comingSoon,
                icon: const Icon(Icons.add, size: 14, color: AppColors.primary),
                label: Text(
                  'Create Group',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: list
                .map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _GroupListTile(
                      group: g,
                      state: _states[g.name] ?? g.action,
                      onAction: () => _toggle(g.name),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _FeaturedGroupCard extends StatelessWidget {
  final String state;
  final VoidCallback onAction;
  const _FeaturedGroupCard({required this.state, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 108,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppColors.primaryPale),
                Positioned(
                  right: -20,
                  top: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: 0.55,
                    child: Image.asset(
                      'assets/images/school.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryPale.withValues(alpha: 0.98),
                        AppColors.primaryPale.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 15,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'FEATURED',
                      style: GoogleFonts.dmSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 15,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pre-Health Society',
                        style: GoogleFonts.dmSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        '98 members · Academic',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'For students pursuing careers in medicine, nursing, and public health.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _GroupActionBtn(state: state, onTap: onAction),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupListTile extends StatelessWidget {
  final PlaceholderGroup group;
  final String state;
  final VoidCallback onAction;
  const _GroupListTile({
    required this.group,
    required this.state,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: group.greenTone
                  ? const Color(0xFFECFDF5)
                  : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: group.useLc
                ? Text(
                    'LC',
                    style: GoogleFonts.dmSans(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  )
                : Icon(
                    group.iconData,
                    size: 18,
                    color: group.greenTone
                        ? AppColors.green
                        : AppColors.primary,
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  '${group.category} · ${group.members} members',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _GroupActionBtn(state: state, onTap: onAction),
        ],
      ),
    );
  }
}

class _GroupActionBtn extends StatelessWidget {
  final String state;
  final VoidCallback onTap;
  const _GroupActionBtn({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (bg, border, color) = switch (state) {
      'Join' => (AppColors.primary, AppColors.primary, Colors.white),
      'Joined' => (AppColors.surface, AppColors.border, AppColors.textMid),
      'Request' => (AppColors.surface, AppColors.primary, AppColors.primary),
      _ => (AppColors.surface, AppColors.border, AppColors.textMuted),
    };

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Text(
            state,
            style: GoogleFonts.dmSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

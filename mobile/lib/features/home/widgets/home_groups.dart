part of '../screens/home_screen.dart';

class _PlaceholderGroup {
  final String name;
  final String members;
  final IconData? icon;
  final bool useLc;
  final bool greenTone;
  const _PlaceholderGroup({
    required this.name,
    required this.members,
    this.icon,
    this.useLc = false,
    this.greenTone = false,
  });
}

const _homeGroups = [
  _PlaceholderGroup(
    name: 'Livingstone Volleyball',
    members: '124 members',
    useLc: true,
  ),
  _PlaceholderGroup(
    name: 'Pre-Health Society',
    members: '98 members',
    icon: Icons.favorite_border_rounded,
  ),
  _PlaceholderGroup(
    name: 'Tech Club',
    members: '76 members',
    icon: Icons.code_rounded,
  ),
  _PlaceholderGroup(
    name: "Men's Mentorship",
    members: '85 members',
    icon: Icons.groups_outlined,
    greenTone: true,
  ),
];

class _CampusGroupsRow extends StatelessWidget {
  const _CampusGroupsRow();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Row(
        children: [
          ..._homeGroups.map(
            (g) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => context.go('/discover?tab=groups'),
                child: Container(
                  width: 122,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0D111827),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: g.greenTone
                              ? const Color(0xFFECFDF5)
                              : AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: g.useLc
                            ? Text(
                                'LC',
                                style: GoogleFonts.dmSans(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              )
                            : Icon(
                                g.icon,
                                size: 18,
                                color: g.greenTone
                                    ? AppColors.green
                                    : AppColors.primary,
                              ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        g.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        g.members,
                        style: GoogleFonts.dmSans(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

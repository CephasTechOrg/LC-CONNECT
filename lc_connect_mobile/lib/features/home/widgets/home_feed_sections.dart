part of '../screens/home_screen.dart';

// ── Search bar ───────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => context.go('/discover'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
              const SizedBox(width: 8),
              Text(
                'Search people, interests, or activities',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category chips ───────────────────────────────────────────────
class _CategoryChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _CategoryChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          ..._cats.map((cat) {
            final on = selected == cat.label;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => onSelect(cat.label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  constraints: const BoxConstraints(minWidth: 72),
                  decoration: BoxDecoration(
                    color: on ? AppColors.primarySoft : AppColors.surface,
                    border: Border.all(
                      color: on ? AppColors.primary : AppColors.border,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat.icon,
                        size: 20,
                        color: on ? AppColors.primary : AppColors.textMuted,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        cat.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                          color: on ? AppColors.primary : AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          GestureDetector(
            onTap: onAction,
            child: Text(
              action,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

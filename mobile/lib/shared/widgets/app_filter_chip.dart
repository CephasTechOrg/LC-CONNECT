import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

/// Selected/unselected pill used on Connect, Activities, Groups filters.
class AppFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: Alignment.center,
              // Shrink to the pill. Without it the Align took the full width wherever the chip
              // got a bounded width — in a Wrap every chip sat alone on its own line.
              widthFactor: 1,
              // Soft selected state (tint + accent text), matching the Messages
              // Chats/Groups track, rather than a solid fill competing with the
              // screen's primary buttons.
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primarySoft : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.35)
                        : AppColors.border,
                  ),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      // primaryText, not primary: brand blue on the soft tint is under AA.
                      color: selected ? AppColors.primaryText : AppColors.textMid,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppFilterChipRow extends StatelessWidget {
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelect;
  final EdgeInsetsGeometry padding;

  const AppFilterChipRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final label in labels)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppFilterChip(
                label: label,
                selected: selected == label,
                onTap: () => onSelect(label),
              ),
            ),
        ],
      ),
    );
  }
}

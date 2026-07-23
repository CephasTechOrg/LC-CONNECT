part of '../screens/activities_screen.dart';

class _FilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _FilterChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: _filters.map((f) {
          final (code, label) = f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppFilterChip(
              label: label,
              selected: selected == code,
              onTap: () => onSelect(code),
            ),
          );
        }).toList(),
      ),
    );
  }
}

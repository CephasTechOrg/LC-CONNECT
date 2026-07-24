import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';

/// A clean, reusable search box. Shows a clear button once there's text; debouncing is the
/// caller's job (so each screen can tune it).
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final EdgeInsetsGeometry padding;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hasText,
    required this.onChanged,
    required this.onClear,
    this.hint = 'Search',
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 8),
  });

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color));

    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMuted),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: border(AppColors.border),
          enabledBorder: border(AppColors.border),
          focusedBorder: border(AppColors.primary),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// The one text field every auth screen uses.
///
/// It exists because register, forgot-password, reset and verify-email each had their own copy
/// that wrapped a [TextFormField] in a **fixed-height [Container]** with
/// `errorBorder: InputBorder.none`. With no room below the input, Flutter drew the validation
/// message *inside* the box, overlapping the value the user had typed — measured at 9.5px of
/// overlap on the register screen. Letting the decorator size itself is the whole fix, so this
/// widget deliberately sets no height.
///
/// [autofillHints] and [textInputAction] are first-class here rather than optional extras: no auth
/// field previously set either, so password managers never offered to fill or save anything and the
/// keyboard's return key did nothing.
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData? icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final int? maxLength;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;
  final TextAlign textAlign;
  final TextStyle? textStyle;
  final String? hintOverrideStyleFont;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.suffixIcon,
    this.maxLength,
    this.validator,
    this.inputFormatters,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.textAlign = TextAlign.start,
    this.textStyle,
    this.hintOverrideStyleFont,
  });

  OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLength: maxLength,
      validator: validator,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      textAlign: textAlign,
      style: textStyle ??
          GoogleFonts.dmSans(fontSize: 15, color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: textStyle?.copyWith(color: const Color(0xFFB6BECA)) ??
            GoogleFonts.dmSans(fontSize: 15, color: const Color(0xFF9CA3AF)),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffixIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: suffixIcon,
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        // Every state gets a real border — including the two error states, which is exactly what
        // the old copies set to `InputBorder.none`.
        border: _border(AppColors.border),
        enabledBorder: _border(AppColors.border),
        focusedBorder: _border(AppColors.primary, width: 1.5),
        errorBorder: _border(AppColors.error),
        focusedErrorBorder: _border(AppColors.error, width: 1.5),
        errorStyle: GoogleFonts.dmSans(fontSize: 12, color: AppColors.error, height: 1.3),
        errorMaxLines: 2,
      ),
    );
  }
}

/// Full-width gradient button shared by the auth screens.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  final double height;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onTap,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !loading,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF5A94C2), Color(0xFF3E7EB4)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authNotifierProvider.notifier).register(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
    if (!mounted) return;
    final error = ref.read(authNotifierProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString(),
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    // On success the router redirect handles navigation based on isVerified/profileCompleted.
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Branding(),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MockupField(
                        controller:   _emailCtrl,
                        hintText:     'College email address',
                        icon:         Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || !v.contains('@')) return 'Enter a valid email';
                          final emailLower = v.toLowerCase().trim();
                          const allowedTestEmails = [
                            'cephas.bonsuosei@gmail.com',
                            'asiedudev.hub@gmail.com',
                            'asieduminta27@gmail.com',
                            'auralenx.team@gmail.com',
                            'bdoreen889@gmail.com',
                          ];
                          if (allowedTestEmails.contains(emailLower)) return null; // Allow test emails
                          
                          final domain = emailLower.split('@').last;
                          if (domain != 'students.livingstone.edu' &&
                              domain != 'livingstone.edu') {
                            return 'Use your Livingstone College email\n(@students.livingstone.edu)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _MockupField(
                        controller:  _passwordCtrl,
                        hintText:    'Password',
                        icon:        Icons.lock_outline_rounded,
                        obscureText: _obscure,
                        suffixIcon: GestureDetector(
                          onTap: () => setState(() => _obscure = !_obscure),
                          child: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        ),
                        validator: (v) => v != null && v.length >= 6 ? null : 'Min 6 characters',
                      ),
                      const SizedBox(height: 12),
                      _MockupField(
                        controller:  _confirmCtrl,
                        hintText:    'Confirm password',
                        icon:        Icons.lock_reset_rounded,
                        obscureText: _obscure,
                        validator: (v) => v == _passwordCtrl.text ? null : 'Passwords do not match',
                      ),
                      const SizedBox(height: 24),
                      _ActionButton(
                        label: 'Create Account',
                        isLoading: isLoading,
                        onTap: _submit,
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: GestureDetector(
                          onTap: () => context.go('/login'),
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                color: AppColors.textMid,
                              ),
                              children: [
                                const TextSpan(text: "Already have an account?"),
                                TextSpan(
                                  text: ' Sign In',
                                  style: GoogleFonts.dmSans(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _NoteBox(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Branding (same as Login) ─────────────────────────────────────
class _Branding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: [
          Image.asset(
            'assets/images/lclogo.png',
            width: 40,
            height: 40,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LC Connect',
                  style: GoogleFonts.dmSans(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: -0.75,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Join the Livingstone College network',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: AppColors.textMuted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Field Pattern (same as Login) ────────────────────────────────
class _MockupField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _MockupField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller:   controller,
        keyboardType: keyboardType,
        obscureText:  obscureText,
        validator:    validator,
        style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textMid),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.dmSans(fontSize: 15, color: const Color(0xFF9CA3AF)),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Icon(icon, size: 20, color: AppColors.textMid),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: suffixIcon,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border:       InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder:   InputBorder.none,
          filled: false,
        ),
      ),
    );
  }
}

// ── Gradient Action Button ───────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5A94C2), Color(0xFF3E7EB4)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(87),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
    );
  }
}

// ── Note Box (same as Login) ─────────────────────────────────────
class _NoteBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(15),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 24, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.dmSans(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                  height: 1.3,
                ),
                children: [
                  TextSpan(
                    text: 'Students only. ',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  const TextSpan(
                    text: 'Verified Livingstone College students can access LC Connect.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

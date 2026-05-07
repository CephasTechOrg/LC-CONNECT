import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.dio.post('/auth/forgot-password', data: {
        'email': _emailCtrl.text.trim().toLowerCase(),
      });
      if (!mounted) return;
      // Navigate to reset screen regardless — prevents email enumeration
      context.push('/reset-password', extra: _emailCtrl.text.trim().toLowerCase());
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Color(0xFF111827)),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      size: 32, color: Color(0xFF4F8FC2)),
                ),
                const SizedBox(height: 20),
                Text(
                  'Forgot password?',
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Enter your email address and we'll send you a 6-digit reset code.",
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: const Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Email field
                _InputField(
                  controller: _emailCtrl,
                  hintText: 'Email address',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      v != null && v.contains('@') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 24),
                // Submit button
                _PrimaryButton(
                  label: 'Send reset code',
                  loading: _loading,
                  onTap: _submit,
                ),
                const SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: Text(
                      'Back to sign in',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: const Color(0xFF4F8FC2),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reset password screen ─────────────────────────────────────────

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _success = false;

  @override
  void dispose() {
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.dio.post('/auth/reset-password', data: {
        'email': widget.email,
        'otp': _otpCtrl.text.trim(),
        'new_password': _passwordCtrl.text,
      });
      if (!mounted) return;
      setState(() => _success = true);
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Color(0xFF111827)),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: _success ? _SuccessView(onLogin: () => context.go('/login')) : _Form(
            formKey: _formKey,
            email: widget.email,
            otpCtrl: _otpCtrl,
            passwordCtrl: _passwordCtrl,
            confirmCtrl: _confirmCtrl,
            loading: _loading,
            obscurePassword: _obscurePassword,
            obscureConfirm: _obscureConfirm,
            onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
            onToggleConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
            onSubmit: _submit,
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final String email;
  final TextEditingController otpCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool loading;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final VoidCallback onSubmit;

  const _Form({
    required this.formKey,
    required this.email,
    required this.otpCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.loading,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.mark_email_read_outlined,
                size: 32, color: Color(0xFF4F8FC2)),
          ),
          const SizedBox(height: 20),
          Text(
            'Enter your reset code',
            style: GoogleFonts.dmSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: const Color(0xFF6B7280), height: 1.5),
              children: [
                const TextSpan(text: 'We sent a 6-digit code to '),
                TextSpan(
                  text: email,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827)),
                ),
                const TextSpan(text: '. Enter it below along with your new password.'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // OTP field
          _InputField(
            controller: otpCtrl,
            hintText: '6-digit code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: (v) {
              if (v == null || v.length != 6) return 'Enter the 6-digit code';
              if (int.tryParse(v) == null) return 'Code must be numbers only';
              return null;
            },
          ),
          const SizedBox(height: 12),
          // New password
          _InputField(
            controller: passwordCtrl,
            hintText: 'New password',
            icon: Icons.lock_outline_rounded,
            obscureText: obscurePassword,
            suffixIcon: GestureDetector(
              onTap: onTogglePassword,
              child: Icon(
                obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFF7B8494),
                size: 18,
              ),
            ),
            validator: (v) =>
                v != null && v.length >= 8 ? null : 'At least 8 characters',
          ),
          const SizedBox(height: 12),
          // Confirm password
          _InputField(
            controller: confirmCtrl,
            hintText: 'Confirm new password',
            icon: Icons.lock_outline_rounded,
            obscureText: obscureConfirm,
            suffixIcon: GestureDetector(
              onTap: onToggleConfirm,
              child: Icon(
                obscureConfirm
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFF7B8494),
                size: 18,
              ),
            ),
            validator: (v) =>
                v == passwordCtrl.text ? null : 'Passwords do not match',
          ),
          const SizedBox(height: 24),
          _PrimaryButton(
            label: 'Reset password',
            loading: loading,
            onTap: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final VoidCallback onLogin;
  const _SuccessView({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                size: 44, color: Color(0xFF10B981)),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Password reset!',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your password has been updated successfully.\nYou can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: const Color(0xFF6B7280),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 36),
        _PrimaryButton(label: 'Back to sign in', loading: false, onTap: onLogin),
      ],
    );
  }
}

// ── Shared input field ────────────────────────────────────────────
class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final int? maxLength;
  final String? Function(String?)? validator;

  const _InputField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.suffixIcon,
    this.maxLength,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDFE6EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLength: maxLength,
        validator: validator,
        style: GoogleFonts.dmSans(fontSize: 15, color: const Color(0xFF1F2937)),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle:
              GoogleFonts.dmSans(fontSize: 15, color: const Color(0xFF8B91A0)),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Icon(icon, size: 20, color: const Color(0xFF1F2937)),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: suffixIcon,
                )
              : null,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }
}

// ── Shared primary button ─────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _PrimaryButton(
      {required this.label, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
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
              color: const Color(0xFF3F7FB5).withAlpha(87),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
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
    );
  }
}

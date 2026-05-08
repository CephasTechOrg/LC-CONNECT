import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpCtrl = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.dio.post('/auth/verify-email', data: {
        'otp': _otpCtrl.text.trim(),
      });
      if (!mounted) return;
      // Update auth state — GoRouter redirect fires automatically via refreshListenable.
      await ref.read(authNotifierProvider.notifier).refreshVerification();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(_snackBar(msg, isError: true));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _resending) return;
    setState(() => _resending = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.dio.post('/auth/resend-verification');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('Code resent. Check your Livingstone email.', isError: false),
      );
      _startCooldown(60);
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Could not resend. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(_snackBar(msg, isError: true));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _signOut() async {
    await ref.read(authNotifierProvider.notifier).logout();
  }

  SnackBar _snackBar(String msg, {required bool isError}) => SnackBar(
        content: Text(msg, style: GoogleFonts.dmSans()),
        backgroundColor: isError ? AppColors.error : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authNotifierProvider).value?.email ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 36,
                      color: Color(0xFF4F8FC2),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                Text(
                  'Check your email',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: const Color(0xFF6B7280),
                      height: 1.6,
                    ),
                    children: [
                      const TextSpan(text: 'We sent a 6-digit verification code to\n'),
                      TextSpan(
                        text: email,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const TextSpan(text: '\nEnter it below to verify your account.'),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // OTP field
                _OtpField(controller: _otpCtrl),
                const SizedBox(height: 20),

                // Verify button
                _PrimaryButton(
                  label: 'Verify email',
                  loading: _loading,
                  onTap: _verify,
                ),
                const SizedBox(height: 28),

                // Resend row
                Center(
                  child: _resendCooldown > 0
                      ? Text(
                          'Resend code in ${_resendCooldown}s',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            color: const Color(0xFF9CA3AF),
                          ),
                        )
                      : GestureDetector(
                          onTap: _resending ? null : _resend,
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                color: const Color(0xFF6B7280),
                              ),
                              children: [
                                const TextSpan(text: "Didn't receive it? "),
                                TextSpan(
                                  text: _resending ? 'Sending…' : 'Resend code',
                                  style: GoogleFonts.dmSans(
                                    color: const Color(0xFF4F8FC2),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 48),

                // Sign out
                Center(
                  child: GestureDetector(
                    onTap: _signOut,
                    child: Text(
                      'Wrong account? Sign out',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: const Color(0xFF9CA3AF),
                        decoration: TextDecoration.underline,
                        decorationColor: const Color(0xFF9CA3AF),
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

// ── OTP input field ───────────────────────────────────────────────
class _OtpField extends StatelessWidget {
  final TextEditingController controller;
  const _OtpField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
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
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSans(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 10,
          color: const Color(0xFF111827),
        ),
        validator: (v) {
          if (v == null || v.length != 6) return 'Enter the 6-digit code';
          if (int.tryParse(v) == null) return 'Numbers only';
          return null;
        },
        decoration: InputDecoration(
          hintText: '······',
          hintStyle: GoogleFonts.dmSans(
            fontSize: 28,
            letterSpacing: 10,
            color: const Color(0xFFD1D5DB),
          ),
          counterText: '',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }
}

// ── Primary button ────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 50,
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
                  width: 22,
                  height: 22,
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

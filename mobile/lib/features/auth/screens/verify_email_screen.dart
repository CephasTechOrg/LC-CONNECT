import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/auth_error_messages.dart';
import '../data/otp_config.dart';
import '../widgets/auth_text_field.dart';
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
      final notifier = ref.read(authNotifierProvider.notifier);
      final email = notifier.pendingEmail ??
          ref.read(authNotifierProvider).asData?.value?.email;
      if (email == null || email.isEmpty) {
        throw StateError('Missing email for verification.');
      }
      await notifier.verifyEmailOtp(email: email, token: _otpCtrl.text.trim());
    } catch (e) {
      if (!mounted) return;
      // The backend's own `detail` is already user-facing copy, so it is preferred when the
      // failure came from us; anything from Supabase goes through the mapper.
      final msg = e is DioException
          ? ((e.response?.data as Map?)?['detail'] as String? ??
              'Something went wrong. Please try again.')
          : authErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(_snackBar(msg, isError: true));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _resending) return;
    setState(() => _resending = true);
    try {
      final notifier = ref.read(authNotifierProvider.notifier);
      final email = notifier.pendingEmail ??
          ref.read(authNotifierProvider).asData?.value?.email;
      if (email == null || email.isEmpty) {
        throw StateError('Missing email for resend.');
      }
      await notifier.resendSignupOtp(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('Code resent. Check your personal email inbox.', isError: false),
      );
      _startCooldown(60);
    } catch (e) {
      if (!mounted) return;
      final msg = authErrorMessage(e);
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

  Future<void> _backToLogin() async {
    await ref.read(authNotifierProvider.notifier).cancelEmailConfirmation();
    if (!mounted) return;
    context.go('/login');
  }

  SnackBar _snackBar(String msg, {required bool isError}) => SnackBar(
        content: Text(msg, style: GoogleFonts.dmSans()),
        backgroundColor: isError ? AppColors.error : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(authNotifierProvider.notifier);
    final displayEmail = notifier.pendingContactEmail ??
        notifier.pendingEmail ??
        ref.watch(authNotifierProvider).value?.email ??
        '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Color(0xFF111827)),
          onPressed: _backToLogin,
          tooltip: 'Back to login',
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
                      TextSpan(text: 'We sent a $kOtpLength-digit verification code to\n'),
                      TextSpan(
                        text: displayEmail.isEmpty ? 'your personal email' : displayEmail,
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
                AuthTextField(
                  controller: _otpCtrl,
                  hintText: '·' * kOtpLength,
                  keyboardType: TextInputType.number,
                  maxLength: kOtpLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _verify(),
                  textAlign: TextAlign.center,
                  textStyle: GoogleFonts.dmSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 8,
                    color: AppColors.textDark,
                  ),
                  validator: (v) => (v != null && v.length == kOtpLength)
                      ? null
                      : 'Enter the $kOtpLength-digit code',
                ),
                const SizedBox(height: 20),

                // Verify button
                AuthPrimaryButton(
                  label: 'Verify email',
                  loading: _loading,
                  onTap: _verify,
                  height: 50,
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

                // Back to login
                Center(
                  child: GestureDetector(
                    onTap: _backToLogin,
                    child: Text(
                      'Back to login',
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

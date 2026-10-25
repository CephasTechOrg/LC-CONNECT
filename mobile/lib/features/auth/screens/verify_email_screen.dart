import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../data/auth_error_messages.dart';
import '../data/otp_config.dart';
import '../widgets/auth_page_parts.dart';
import '../widgets/auth_text_field.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
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
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : const Color(0xFF15803D),
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
              size: 18, color: AppColors.textDark),
          onPressed: _backToLogin,
          tooltip: 'Back to sign in',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.sm, AppSpacing.xxl, AppSpacing.xxxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthHeading(
                  icon: Icons.mark_email_unread_outlined,
                  title: 'Check your email',
                  subtitle: [
                    // No article before the number: "a" read wrong before eight, and "an" would
                    // read wrong before six if the code length ever changes.
                    const TextSpan(text: 'We sent a code to '),
                    authEmphasis(displayEmail.isEmpty ? 'your personal email' : displayEmail),
                    // Non-breaking space: the count and its noun stay on one line.
                    TextSpan(text: '. Enter the $kOtpLength\u00A0digits below to verify your account.'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
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
                  textStyle: AppTypography.display.copyWith(
                    letterSpacing: 8,
                    color: AppColors.textDark,
                  ),
                  validator: (v) => (v != null && v.length == kOtpLength)
                      ? null
                      : 'Enter the $kOtpLength-digit code',
                ),
                const SizedBox(height: 20),

                AuthPrimaryButton(
                  label: 'Verify email',
                  loading: _loading,
                  onTap: _verify,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_resendCooldown > 0)
                  SizedBox(
                    height: kMinInteractiveDimension,
                    child: Center(
                      child: Text(
                        'Resend code in ${_resendCooldown}s',
                        style: AppTypography.body.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  )
                else
                  AuthTextLink(
                    label: _resending ? 'Sending…' : 'Resend code',
                    onTap: _resending ? null : _resend,
                  ),
                // Same words as every other auth screen: "sign in", never "login".
                AuthTextLink(label: 'Back to sign in', muted: true, onTap: _backToLogin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

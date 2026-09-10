import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../data/auth_error_messages.dart';
import '../data/otp_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_text_field.dart';

/// Code-entry + new-password step of the reset flow.
///
/// [email] is null whenever the screen is reached without navigation state — a hot restart while
/// sitting here, a deep link, restored navigation. That used to be
/// `ResetPasswordScreen(email: state.extra as String)` in the router, which threw
/// `type 'Null' is not a subtype of type 'String' in type cast` and showed a red screen instead of
/// the form. Now the email simply becomes one more field in the same form, so there is no separate
/// mode to fall into and the flow is re-enterable from cold.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String? email;
  const ResetPasswordScreen({super.key, this.email});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _resending = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _success = false;

  /// True when we arrived without an email and must ask for it inline.
  bool get _needsEmail => widget.email == null;

  String get _email =>
      (widget.email ?? _emailCtrl.text).trim().toLowerCase();

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      _snack(authErrorMessage(error), isError: true),
    );
  }

  SnackBar _snack(String msg, {required bool isError}) => SnackBar(
        content: Text(msg, style: GoogleFonts.dmSans()),
        backgroundColor: isError ? AppColors.error : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  Future<void> _submit() async {
    if (_loading) return; // guards double-submit
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authNotifierProvider.notifier).resetPasswordWithOtp(
            email: _email,
            token: _otpCtrl.text.trim(),
            newPassword: _passwordCtrl.text,
          );
      if (!mounted) return;
      setState(() => _success = true);
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// An expired code used to be a dead end: the error told the user to request a new one, and
  /// this screen had no way to do it. Mirrors the verify-email screen's resend + cooldown.
  Future<void> _resend() async {
    if (_resendCooldown > 0 || _resending) return;
    final email = _email;
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Enter your Livingstone email first.', isError: true),
      );
      return;
    }
    setState(() => _resending = true);
    try {
      await ref.read(authNotifierProvider.notifier).sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('New code sent. Check your personal email inbox.', isError: false),
      );
      _startCooldown(60);
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      if (mounted) setState(() => _resending = false);
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
              size: 18, color: AppColors.textDark),
          onPressed: _loading ? null : () => context.pop(),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: _success
              ? _SuccessView(onLogin: () => context.go('/login'))
              : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryPale,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.mark_email_read_outlined,
                  size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Enter your reset code',
              style: GoogleFonts.dmSans(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            _subtitle(),
            const SizedBox(height: 28),
            if (_needsEmail) ...[
              AuthTextField(
                controller: _emailCtrl,
                hintText: 'you@students.livingstone.edu',
                icon: Icons.school_outlined,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                validator: (v) => (v != null && v.contains('@'))
                    ? null
                    : 'Enter your Livingstone email',
              ),
              const SizedBox(height: 12),
            ],
            AuthTextField(
              controller: _otpCtrl,
              hintText: '$kOtpLength-digit code',
              icon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              maxLength: kOtpLength,
              // keyboardType is only a hint — hardware and third-party keyboards ignore it, and a
              // pasted code can carry spaces. This makes digits-only actually true.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.next,
              validator: (v) => (v != null && v.length == kOtpLength)
                  ? null
                  : 'Enter the $kOtpLength-digit code',
            ),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _passwordCtrl,
              hintText: 'New password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              suffixIcon: _EyeToggle(
                obscured: _obscurePassword,
                onTap: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) =>
                  v != null && v.length >= 8 ? null : 'At least 8 characters',
            ),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _confirmCtrl,
              hintText: 'Confirm new password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureConfirm,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              suffixIcon: _EyeToggle(
                obscured: _obscureConfirm,
                onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              validator: (v) =>
                  v == _passwordCtrl.text ? null : 'Passwords do not match',
            ),
            const SizedBox(height: 24),
            AuthPrimaryButton(
              label: 'Reset password',
              loading: _loading,
              onTap: _submit,
            ),
            const SizedBox(height: 22),
            Center(child: _resendRow()),
          ],
        ),
      ),
    );
  }

  Widget _subtitle() {
    final style = GoogleFonts.dmSans(
        fontSize: 14, color: AppColors.textMuted, height: 1.5);
    if (_needsEmail) {
      return Text(
        'Enter your Livingstone email and the $kOtpLength-digit code we sent to your personal '
        'inbox, then choose a new password.',
        style: style,
      );
    }
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: 'We sent a $kOtpLength-digit code to the personal inbox for '),
          TextSpan(
            text: widget.email,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          const TextSpan(text: '. Enter it below along with your new password.'),
        ],
      ),
    );
  }

  Widget _resendRow() {
    if (_resendCooldown > 0) {
      return Text(
        'Resend code in ${_resendCooldown}s',
        style: GoogleFonts.dmSans(fontSize: 14, color: const Color(0xFF9CA3AF)),
      );
    }
    return GestureDetector(
      onTap: _resending ? null : _resend,
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMuted),
          children: [
            const TextSpan(text: 'Code expired or never arrived? '),
            TextSpan(
              text: _resending ? 'Sending…' : 'Send a new one',
              style: GoogleFonts.dmSans(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _EyeToggle extends StatelessWidget {
  final bool obscured;
  final VoidCallback onTap;
  const _EyeToggle({required this.obscured, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: AppColors.textMuted,
        size: 18,
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
          'Password reset',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your password has been updated.\nSign in with your new password.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: AppColors.textMuted,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 36),
        AuthPrimaryButton(label: 'Back to sign in', loading: false, onTap: onLogin),
      ],
    );
  }
}

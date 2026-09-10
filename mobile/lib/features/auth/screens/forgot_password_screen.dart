import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../data/auth_error_messages.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_text_field.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _isCampusDomain(String emailLower) {
    final domain = emailLower.split('@').last;
    return domain == 'students.livingstone.edu' || domain == 'livingstone.edu';
  }

  /// The reset targets the *account* address (the Livingstone email), never the personal inbox —
  /// that only receives the code. Entering the personal email here looks like it worked (Supabase
  /// reports success for unknown addresses to prevent enumeration) but no code is ever sent,
  /// stranding the user on the code screen. Validate up front so that dead end can't happen.
  String? _validateEmail(String? v) {
    if (v == null || !v.contains('@')) return 'Enter a valid email';
    if (!_isCampusDomain(v.toLowerCase().trim())) {
      return 'Enter your Livingstone email — the account we reset, not your personal one.';
    }
    return null;
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _submit() async {
    if (_loading || _cooldown > 0) return; // double-submit / inbox-bombing guard
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailCtrl.text.trim().toLowerCase();
    try {
      await ref.read(authNotifierProvider.notifier).sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'If that account exists, we sent a code to your personal email.',
          style: GoogleFonts.dmSans(),
        ),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      // The mobile app calls Supabase directly, so the backend's IP + per-address caps on
      // /auth/forgot-password never apply here. Without a local cooldown an impatient double-tap
      // burns the user's own Supabase quota and returns a rate-limit error that reads as failure.
      _startCooldown(60);
      // Go to code entry, NOT back to login. Reset is code-based (the email carries an OTP,
      // deliberately not a magic link — see backend `_cta_button`), so bouncing to sign-in left
      // the user holding a code with nowhere to enter it.
      context.push('/reset-password', extra: email);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(authErrorMessage(e), style: GoogleFonts.dmSans()),
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
              size: 18, color: AppColors.textDark),
          onPressed: _loading ? null : () => context.pop(),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formKey,
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
                  child: const Icon(Icons.lock_reset_rounded,
                      size: 32, color: AppColors.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  'Forgot password?',
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your Livingstone email. We send the reset code to the personal email you '
                  'used at signup.',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                AuthTextField(
                  controller: _emailCtrl,
                  hintText: 'you@students.livingstone.edu',
                  icon: Icons.school_outlined,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 24),
                AuthPrimaryButton(
                  label: _cooldown > 0
                      ? 'Send again in ${_cooldown}s'
                      : 'Send reset code',
                  loading: _loading,
                  onTap: _submit,
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: _loading ? null : () => context.push('/reset-password'),
                    child: Text(
                      'I already have a code',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: GestureDetector(
                    onTap: _loading ? null : () => context.pop(),
                    child: Text(
                      'Back to sign in',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.textMuted,
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_error_messages.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_page_parts.dart';
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
      return 'Use your campus email, not your personal one.';
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
        content: const Text('If that account exists, we sent a code to your personal email.'),
        // The AA success green; white on the old #059669 was ~3.8:1.
        backgroundColor: AppColors.green,
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
        content: Text(authErrorMessage(e)),
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
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.sm, AppSpacing.xxl, AppSpacing.xxxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHeading(
                  icon: Icons.lock_reset_rounded,
                  title: 'Forgot password?',
                  subtitle: [
                    TextSpan(text: 'Enter your campus email. We send the code to your personal inbox.'),
                  ],
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
                const SizedBox(height: AppSpacing.sm),
                AuthTextLink(
                  label: 'I already have a code',
                  onTap: _loading ? null : () => context.push('/reset-password'),
                ),
                AuthTextLink(
                  label: 'Back to sign in',
                  muted: true,
                  onTap: _loading ? null : () => context.pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

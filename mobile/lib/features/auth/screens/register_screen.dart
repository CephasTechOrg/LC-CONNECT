import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_error_messages.dart';
import '../providers/auth_provider.dart';
import '../../policies/data/policy_slugs.dart';
import '../../policies/widgets/policy_links.dart';
import '../widgets/auth_text_field.dart';

part '../widgets/policy_consent_checkbox.dart';
part '../widgets/register_confirm_sheet.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _contactCtrl  = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _obscure = true;
  bool _policiesAccepted = false;


  @override
  void dispose() {
    _emailCtrl.dispose();
    _contactCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _isCampusDomain(String emailLower) {
    final domain = emailLower.split('@').last;
    return domain == 'students.livingstone.edu' || domain == 'livingstone.edu';
  }

  void _backToLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  Future<void> _submit() async {
    // Belt and braces with the disabled button: `onFieldSubmitted` on the last field also calls
    // this, so the keyboard's Done key must not be a way around the checkbox.
    if (!_policiesAccepted) return;
    if (!_formKey.currentState!.validate()) return;

    // Confirm both addresses before the account exists. Once Supabase has the signup, the campus
    // email is the account's identity and a typo in it can only be undone by an admin — see
    // `_showRegisterConfirmSheet` for why the campus one is the dangerous half.
    final confirmed = await _showRegisterConfirmSheet(
      context,
      campusEmail: _emailCtrl.text.trim().toLowerCase(),
      contactEmail: _contactCtrl.text.trim().toLowerCase(),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(authNotifierProvider.notifier).register(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          contactEmail: _contactCtrl.text.trim(),
          policiesAcceptedVersion: kPolicyVersion,
        );
    if (!mounted) return;
    final error = ref.read(authNotifierProvider).error;
    if (error != null) {
      // "Try signing in instead" is only useful if signing in is one tap away. The link that does
      // it sits below four fields and a button, off-screen at the moment the error appears.
      final alreadyRegistered =
          error is AuthException && error.code == 'user_already_exists';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authErrorMessage(error),
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: alreadyRegistered ? 8 : 4),
          action: alreadyRegistered
              ? SnackBarAction(
                  label: 'Sign in',
                  textColor: Colors.white,
                  onPressed: _backToLogin,
                )
              : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    if (ref.read(authNotifierProvider.notifier).awaitingEmailConfirmation) {
      context.go('/verify-email');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      // Login `push`es here, so the platform back gesture already works; this makes the way
      // back discoverable too. Without either, the only exit was the "Sign In" line at the
      // very bottom of a scrolling form, and Android's back gesture left the app entirely.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Branding(),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Form(
                  key: _formKey,
                  // Lets iOS Keychain / Google Password Manager offer to save the new credential
                  // as one unit once the form is submitted.
                  child: AutofillGroup(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel(title: 'Official campus email'),
                      const SizedBox(height: 8),
                      AuthTextField(
                        controller:   _emailCtrl,
                        hintText:     'you@students.livingstone.edu',
                        icon:         Icons.school_outlined,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || !v.contains('@')) return 'Enter a valid email';
                          final emailLower = v.toLowerCase().trim();
                          if (!_isCampusDomain(emailLower)) {
                            return 'Use your Livingstone College email (@students.livingstone.edu)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const _FieldLabel(title: 'Personal email (for your code)'),
                      const SizedBox(height: 8),
                      AuthTextField(
                        controller:   _contactCtrl,
                        hintText:     'you@gmail.com',
                        icon:         Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || !v.contains('@')) return 'Enter a valid personal email';
                          final emailLower = v.toLowerCase().trim();
                          if (_isCampusDomain(emailLower)) {
                            return 'Use a personal email, not your Livingstone address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller:  _passwordCtrl,
                        hintText:    'Password',
                        icon:        Icons.lock_outline_rounded,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
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
                        // Matches the 8-character minimum the reset screen and both web portals
                        // already enforce; 6 here contradicted every other surface.
                        validator: (v) => v != null && v.length >= 8 ? null : 'At least 8 characters',
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller:  _confirmCtrl,
                        hintText:    'Confirm password',
                        icon:        Icons.lock_reset_rounded,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => v == _passwordCtrl.text ? null : 'Passwords do not match',
                      ),
                      const SizedBox(height: 20),
                      _PolicyConsentCheckbox(
                        accepted: _policiesAccepted,
                        onChanged: (value) =>
                            setState(() => _policiesAccepted = value),
                      ),
                      const SizedBox(height: 20),
                      _ActionButton(
                        label: 'Create Account',
                        isLoading: isLoading,
                        // Disabled rather than tappable-then-refused: a button that looks ready
                        // and then tells you no is worse than one that visibly is not ready yet.
                        enabled: _policiesAccepted,
                        onTap: _submit,
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: GestureDetector(
                          onTap: _backToLogin,
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
                    ],
                    ),
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
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Row(
        children: [
          Image.asset(
            'assets/images/lclogo.webp',
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
                  'Create your account',
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

// ── Field label ─────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String title;

  const _FieldLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
    );
  }
}

// ── Gradient Action Button ───────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;
  final bool enabled;
  const _ActionButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !isLoading;
    return Opacity(
      opacity: active ? 1 : 0.45,
      child: GestureDetector(
      onTap: active ? onTap : null,
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
      ),
    );
  }
}

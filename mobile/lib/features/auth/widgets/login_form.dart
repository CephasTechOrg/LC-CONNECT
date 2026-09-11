part of '../screens/login_screen.dart';

/// Sign-in accepts the campus address only — it is the account identity. The personal address
/// receives every code but is not an auth identity in Supabase, so it can never sign anyone in.
String? _validateCampusEmail(String? v) {
  if (v == null || !v.contains('@')) return 'Enter a valid email';
  final domain = v.toLowerCase().trim().split('@').last;
  if (domain != 'students.livingstone.edu' && domain != 'livingstone.edu') {
    return "That's not a Livingstone address.";
  }
  return null;
}

/// Brand + email/password + sign-in (scrolls when the keyboard is up).
class _SignInFields extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final bool isLoading;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  const _SignInFields({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.isLoading,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _LcBadge(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LC Connect',
                    style: GoogleFonts.dmSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      letterSpacing: -0.75,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Campus life, connected',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        AuthTextField(
          controller: emailCtrl,
          hintText: 'you@students.livingstone.edu',
          icon: Icons.school_outlined,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          textInputAction: TextInputAction.next,
          // Only checked `contains('@')`, so 'a@' and a personal address both sailed through to
          // Supabase and came back as "That email or password is incorrect" — sending students to
          // reset a password that was never wrong. Codes go to the personal inbox, so typing it
          // here is the natural mistake; catch it inline with the reason.
          validator: _validateCampusEmail,
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Use your campus email, not your personal one.',
            style: GoogleFonts.dmSans(
              fontSize: 11.5,
              color: AppColors.textMuted,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: passwordCtrl,
          hintText: 'Password',
          icon: Icons.lock_outline_rounded,
          obscureText: obscure,
          suffixIcon: GestureDetector(
            onTap: onToggleObscure,
            child: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.textMuted,
              size: 18,
            ),
          ),
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => onSubmit(),
          validator: (v) =>
              v != null && v.isNotEmpty ? null : 'Enter your password',
        ),
        const SizedBox(height: 18),
        _SignInButton(isLoading: isLoading, onTap: onSubmit),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => context.push('/forgot-password'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Forgot password?',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pinned under the scroll area so tall phones don't leave a blank void.
class _CreateAccountFooter extends StatelessWidget {
  final double bottomInset;
  final VoidCallback onRegister;

  const _CreateAccountFooter({
    required this.bottomInset,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 4, 28, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Divider(color: AppColors.border, thickness: 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'OR',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Expanded(
                child: Divider(color: AppColors.border, thickness: 1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CreateAccountButton(onTap: onRegister),
          const SizedBox(height: 14),
          Text(
            'For Livingstone College students & staff',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

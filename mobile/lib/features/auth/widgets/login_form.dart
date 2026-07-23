part of '../screens/login_screen.dart';

class _FormSection extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final bool isLoading;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onRegister;

  const _FormSection({
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.isLoading,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Row(
              children: [
                const _LcBadge(size: 40),
                const SizedBox(width: 12),
                Text(
                  'LC Connect',
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: -0.75,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Find friends, study partners, and campus groups.',
              style: GoogleFonts.dmSans(
                fontSize: 13.5,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            _MockupField(
              controller: emailCtrl,
              hintText: 'Email address',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
                  v != null && v.contains('@') ? null : 'Enter a valid email',
            ),
            const SizedBox(height: 14),
            _MockupField(
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
            const SizedBox(height: 20),
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
            const SizedBox(height: 20),
            _CreateAccountButton(onTap: onRegister),
          ],
        ),
      ),
    );
  }
}

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
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.dmSans(
          fontSize: 14,
          color: const Color(0xFF9CA3AF),
        ),
        filled: true,
        fillColor: AppColors.background,
        prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
        suffixIcon: suffixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(right: 8),
                child: suffixIcon,
              )
            : null,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 36, minHeight: 36),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }
}

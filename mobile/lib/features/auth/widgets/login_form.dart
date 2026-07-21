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
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email field
            _MockupField(
              controller:   emailCtrl,
              hintText:     'Email address',
              icon:         Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator:    (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
            ),
            const SizedBox(height: 10),
            // Password field
            _MockupField(
              controller:  passwordCtrl,
              hintText:    'Password',
              icon:        Icons.lock_outline_rounded,
              obscureText: obscure,
              suffixIcon: GestureDetector(
                onTap: onToggleObscure,
                child: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _C.eyeColor,
                  size: 18,
                ),
              ),
              validator: (v) => v != null && v.isNotEmpty ? null : 'Enter your password',
            ),
            const SizedBox(height: 6),
            // Forgot password
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => context.push('/forgot-password'),
                child: Text(
                  'Forgot password?',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: _C.forgotBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Sign In button
            _SignInButton(isLoading: isLoading, onTap: onSubmit),
            const SizedBox(height: 14),
            // OR divider
            Row(
              children: [
                const Expanded(child: Divider(color: _C.divLine, thickness: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'OR',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _C.divText,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: _C.divLine, thickness: 1)),
              ],
            ),
            const SizedBox(height: 12),
            // Continue with school email
            _SchoolEmailButton(),
            const SizedBox(height: 14),
            // Create account link
            Center(
              child: GestureDetector(
                onTap: onRegister,
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: _C.createText,
                    ),
                    children: [
                      const TextSpan(text: "Don't have an account?"),
                      TextSpan(
                        text: ' Create account',
                        style: GoogleFonts.dmSans(
                          color: _C.createLink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Students-only note
            _NoteBox(),
          ],
        ),
      ),
    );
  }
}

// ── Mockup-spec input field ───────────────────────────────────────
// White background, 56 px tall, border #DFE6EE, radius 14, subtle shadow.
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
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller:   controller,
        keyboardType: keyboardType,
        obscureText:  obscureText,
        validator:    validator,
        style: GoogleFonts.dmSans(
          fontSize: 15,
          color: _C.textBody,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.dmSans(
            fontSize: 15,
            color: _C.hintColor,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Icon(icon, size: 20, color: _C.textBody),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: suffixIcon,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          // Override all borders so the Container border shows
          border:       InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder:   InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }
}

// ── Sign In gradient button ───────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';

// ── Color palette taken directly from the HTML mockup ─────────────
class _C {
  static const primary      = Color(0xFF4F8FC2);
  static const primaryDark  = Color(0xFF3E7EB4);
  static const logoTop      = Color(0xFF74A5C8);
  static const logoBot      = Color(0xFF5F93BF);
  static const textDark     = Color(0xFF111827);
  static const textBody     = Color(0xFF1F2937);
  static const textMuted    = Color(0xFF565C66);
  static const hintColor    = Color(0xFF8B91A0);
  static const eyeColor     = Color(0xFF7B8494);
  static const border       = Color(0xFFDFE6EE);
  static const forgotBlue   = Color(0xFF3E80BA);
  static const btnShadow    = Color(0xFF3F7FB5);
  static const divLine      = Color(0xFFDFE5EC);
  static const divText      = Color(0xFF6F7784);
  static const outlineBdr   = Color(0xFF3F7FB5);
  static const outlineText  = Color(0xFF1C2635);
  static const createText   = Color(0xFF2E3440);
  static const createLink   = Color(0xFF4E8FC5);
  static const noteIconClr  = Color(0xFF4E8FC5);
  static const noteTextClr  = Color(0xFF606875);
  static const noteStrong   = Color(0xFF1F2937);
  static const noteBg       = Color(0xFFFBFCFD);
  static const noteBorder   = Color(0xFFE0E7EF);
  static const error        = Color(0xFFEF4444);
  static const background   = Color(0xFFF6F9FB);
}

// ── Root widget ──────────────────────────────────────────────────
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authNotifierProvider.notifier).login(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
    if (!mounted) return;
    final error = ref.read(authNotifierProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid email or password. Please try again.',
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: _C.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Branding(),
              _HeroScene(),
              _FormSection(
                formKey:          _formKey,
                emailCtrl:        _emailCtrl,
                passwordCtrl:     _passwordCtrl,
                obscure:          _obscure,
                isLoading:        isLoading,
                onToggleObscure:  () => setState(() => _obscure = !_obscure),
                onSubmit:         _submit,
                onRegister:       () => context.go('/register'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Branding (logo + title + subtitle) ───────────────────────────
class _Branding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo badge — gradient, Georgia "LC", shadow
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_C.logoTop, _C.logoBot],
              ),
              borderRadius: BorderRadius.circular(17),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x38789DBD),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'LC',
              style: TextStyle(
                fontFamily: 'Georgia',
                color: Colors.white,
                fontSize: 32,
                letterSpacing: -4,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.dmSans(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: _C.textDark,
                      height: 0.98,
                      letterSpacing: -2.5,
                    ),
                    children: const [
                      TextSpan(
                        text: 'LC',
                        style: TextStyle(color: _C.primary),
                      ),
                      TextSpan(text: ' Connect'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Find friends, study partners,\nand campus activities',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    color: _C.textMuted,
                    height: 1.35,
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

// ── Hero: school + students + white elliptic curve ────────────────
class _HeroScene extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      margin: const EdgeInsets.only(top: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // School — full-zone background at 45% opacity
          Positioned.fill(
            child: Opacity(
              opacity: 0.45,
              child: Image.asset(
                'assets/images/school.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
          // Students — full-width, pushed a bit below the zone bottom
          Positioned(
            bottom: -80,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/students.png',
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
            ),
          ),
          // White elliptic curve — sits over students' feet
          Positioned(
            bottom: -80,
            left: -30,
            right: -30,
            child: Container(
              height: 90,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.elliptical(200, 90),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Form section ─────────────────────────────────────────────────
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
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
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
            const SizedBox(height: 13),
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
                  size: 20,
                ),
              ),
              validator: (v) => v != null && v.isNotEmpty ? null : 'Enter your password',
            ),
            const SizedBox(height: 8),
            // Forgot password
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {},
                child: Text(
                  'Forgot password?',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: _C.forgotBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Sign In button
            _SignInButton(isLoading: isLoading, onTap: onSubmit),
            const SizedBox(height: 20),
            // OR divider
            Row(
              children: [
                const Expanded(child: Divider(color: _C.divLine, thickness: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.divText,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: _C.divLine, thickness: 1)),
              ],
            ),
            const SizedBox(height: 17),
            // Continue with school email
            _SchoolEmailButton(),
            const SizedBox(height: 17),
            // Create account link
            Center(
              child: GestureDetector(
                onTap: onRegister,
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
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
            const SizedBox(height: 20),
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
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: TextFormField(
        controller:   controller,
        keyboardType: keyboardType,
        obscureText:  obscureText,
        validator:    validator,
        style: GoogleFonts.dmSans(
          fontSize: 16.5,
          color: _C.textBody,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.dmSans(
            fontSize: 16.5,
            color: _C.hintColor,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Icon(icon, size: 22, color: _C.textBody),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: suffixIcon,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
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
class _SignInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _SignInButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5A94C2), Color(0xFF3E7EB4)],
          ),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: _C.btnShadow.withAlpha(87),  // .34 opacity
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Sign In',
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Continue with school email button ────────────────────────────
class _SchoolEmailButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _C.outlineBdr, width: 1.5),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mail_outline_rounded,
                size: 22, color: _C.textBody),
            const SizedBox(width: 16),
            Text(
              'Continue with school email',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _C.outlineText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Students-only note ────────────────────────────────────────────
class _NoteBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        color: _C.noteBg,
        border: Border.all(color: _C.noteBorder),
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(
            color: Color(0x090F172A),  // ~.035 opacity
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined,
              size: 28, color: _C.noteIconClr),
          const SizedBox(width: 13),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.dmSans(
                  fontSize: 13.5,
                  color: _C.noteTextClr,
                  height: 1.38,
                ),
                children: [
                  TextSpan(
                    text: 'Students only. ',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w800,
                      color: _C.noteStrong,
                    ),
                  ),
                  const TextSpan(
                    text: 'Verified Livingstone College students can access LC Connect.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';

part '../widgets/login_branding.dart';
part '../widgets/login_form.dart';
part '../widgets/login_buttons.dart';

// ── Color palette taken directly from the HTML mockup ─────────────
class _C {
  static const primary      = Color(0xFF4F8FC2);
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
    }
    // On success the router redirect handles navigation based on isVerified/profileCompleted.
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_error_messages.dart';
import '../providers/auth_provider.dart';

part '../widgets/login_branding.dart';
part '../widgets/login_form.dart';
part '../widgets/login_buttons.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
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
          // Was hardcoded to "Invalid email or password" for *every* failure, which told a
          // rate-limited or unconfirmed user their password was wrong and hid the real reason.
          content: Text(authErrorMessage(error), style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    // Stronger first impression: hero owns more of the first viewport on tall phones,
    // without crowding the form on short ones.
    final heroH = (screenH * 0.40).clamp(220.0, 320.0);

    // Pin create-account to the bottom (fills tall-phone white space). Keep sign-in fields in
    // a scroll region so the keyboard never hides them. Do NOT put Spacer inside a ScrollView —
    // unbounded height makes the form fail to layout (blank white panel).
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          _HeroScene(height: heroH),
          Expanded(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
                      child: _SignInFields(
                        emailCtrl: _emailCtrl,
                        passwordCtrl: _passwordCtrl,
                        obscure: _obscure,
                        isLoading: isLoading,
                        onToggleObscure: () =>
                            setState(() => _obscure = !_obscure),
                        onSubmit: _submit,
                      ),
                    ),
                  ),
                  _CreateAccountFooter(
                    bottomInset: media.padding.bottom,
                    onRegister: () => context.go('/register'),
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

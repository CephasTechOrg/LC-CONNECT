part of '../screens/profile_screen.dart';

Future<void> _showDeleteAccountFlow(BuildContext context, WidgetRef ref) async {
  final email = ref.read(authNotifierProvider).value?.email;
  if (email == null || !context.mounted) return;

  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DeleteAccountDialog(email: email),
  );
  if (deleted != true || !context.mounted) return;

  ref.invalidate(myProfileNotifierProvider);
  await ref.read(authNotifierProvider.notifier).logout();
  if (!context.mounted) return;
  context.go('/login');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Your account has been deleted.',
        style: GoogleFonts.dmSans(),
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  final String email;

  const _DeleteAccountDialog({required this.email});

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  bool get _emailMatches =>
      _emailCtrl.text.trim().toLowerCase() == widget.email.toLowerCase();

  bool get _canSubmit =>
      _emailMatches && _passwordCtrl.text.isNotEmpty && !_busy;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Delete your account?',
        style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This is permanent. Your profile will be removed, you will be signed out, '
            'and you will not be able to sign back in with this account.',
            style: GoogleFonts.dmSans(color: AppColors.textMid, height: 1.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Type your email to confirm:',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration(hint: widget.email),
          ),
          const SizedBox(height: 14),
          Text(
            'Enter your password to continue:',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordCtrl,
            enabled: !_busy,
            obscureText: _obscure,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_canSubmit) _submit();
            },
            decoration: _fieldDecoration(hint: 'Password').copyWith(
              suffixIcon: IconButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  'Delete account',
                  style: GoogleFonts.dmSans(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(accountServiceProvider).deleteAccount(
            confirmEmail: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage(e, fallback: 'Could not delete your account. Try again.'),
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}

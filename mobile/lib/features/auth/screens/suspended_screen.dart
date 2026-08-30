import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/suspension_provider.dart';

class SuspendedScreen extends ConsumerStatefulWidget {
  const SuspendedScreen({super.key});

  @override
  ConsumerState<SuspendedScreen> createState() => _SuspendedScreenState();
}

class _SuspendedScreenState extends ConsumerState<SuspendedScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAppeal() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await submitSuspensionAppeal(ref, _messageCtrl.text.trim());
      if (!mounted) return;
      _messageCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Appeal submitted. Our team will review it and contact you by email.',
            style: GoogleFonts.dmSans(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data;
      final message = detail is Map ? (detail['detail'] as String?) : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message ?? 'Could not submit appeal. Please try again.', style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suspended = ref.watch(suspendedSessionProvider);
    final statusAsync = ref.watch(suspensionStatusProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Account suspended', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.gavel_outlined, size: 48, color: AppColors.error.withValues(alpha: 0.85)),
              const SizedBox(height: 16),
              Text(
                'Your account has been suspended',
                style: GoogleFonts.dmSans(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                suspended?.email != null
                    ? 'Signed in as ${suspended!.email}. You cannot use LC Connect while suspended.'
                    : 'You cannot use LC Connect while your account is suspended.',
                style: GoogleFonts.dmSans(color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 24),
              statusAsync.when(
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                error: (_, _) => Text(
                  'Could not load appeal status. Tap “Check if account was restored” or sign out and try again.',
                  style: GoogleFonts.dmSans(color: AppColors.textMuted),
                ),
                data: (status) {
                  final support = status.supportEmail;
                  final open = status.openAppeal;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (open != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Appeal under review', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(open.message, style: GoogleFonts.dmSans(height: 1.4)),
                              if (open.adminNote != null && open.adminNote!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('Team note: ${open.adminNote}', style: GoogleFonts.dmSans(fontSize: 13)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'You already have an open appeal. Email $support if you need to add information.',
                          style: GoogleFonts.dmSans(color: AppColors.textMuted, height: 1.4),
                        ),
                      ] else ...[
                        Text(
                          'If you believe this was a mistake, submit a short appeal below. '
                          'This does not automatically restore your account — an administrator will review it.',
                          style: GoogleFonts.dmSans(height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        Form(
                          key: _formKey,
                          child: TextFormField(
                            controller: _messageCtrl,
                            minLines: 4,
                            maxLines: 8,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                              labelText: 'Your message',
                              hintText: 'Explain why you believe your account should be reviewed…',
                              alignLabelWithHint: true,
                            ),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.length < 10) return 'Please write at least 10 characters';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _submitting ? null : _submitAppeal,
                          child: _submitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Submit appeal'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: () => ref.read(authNotifierProvider.notifier).retryAfterSuspension(),
                        child: const Text('Check if account was restored'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Questions? Email $support',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

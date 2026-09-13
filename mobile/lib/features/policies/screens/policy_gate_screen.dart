import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/policy_links.dart';

/// Shown to a signed-in user whose acceptance is missing or out of date.
///
/// Three ways to arrive here:
///   1. an account created before the acceptance gate shipped (the whole pilot, on first launch);
///   2. the backend's policy version was raised, so everyone re-accepts;
///   3. a client that skipped the signup checkbox — which is why this exists server-side at all.
///
/// The signup checkbox is the experience; this is the enforcement.
///
/// The copy is the same for all three. The implementation plan wanted a distinct "we have updated
/// our terms" heading for case 2, but the contract cannot support it: bootstrap returns
/// `policies_accepted` as a **boolean**, so the client cannot tell "never accepted" from "accepted
/// an older version". Adding `policies_accepted_version` to the response would fix that — worth
/// doing when a version 2 actually exists, and not before, since today every arrival is case 1.
class PolicyGateScreen extends ConsumerStatefulWidget {
  const PolicyGateScreen({super.key});

  @override
  ConsumerState<PolicyGateScreen> createState() => _PolicyGateScreenState();
}

class _PolicyGateScreenState extends ConsumerState<PolicyGateScreen> {
  bool _accepted = false;
  bool _saving = false;

  Future<void> _accept() async {
    if (!_accepted || _saving) return;
    setState(() => _saving = true);
    try {
      // On success the auth state updates, the router re-evaluates, and this screen is replaced.
      await ref.read(authNotifierProvider.notifier).acceptPolicies();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage(
              error,
              fallback: "We couldn't save that. Check your connection and try again.",
            ),
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() => ref.read(authNotifierProvider.notifier).logout();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.primaryPale,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.verified_user_outlined,
                          size: 30, color: AppColors.primary),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Before you continue',
                      style: GoogleFonts.dmSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Please review how LC Connect works and how your information is handled, '
                      'then accept to carry on.',
                      style: GoogleFonts.dmSans(
                        fontSize: 14.5,
                        color: AppColors.textMuted,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _GateSummary(),
                    const SizedBox(height: 22),
                    Text(
                      'Read in full',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const PolicyLinkList(),
                  ],
                ),
              ),
            ),
            _GateActions(
              accepted: _accepted,
              saving: _saving,
              onChanged: (value) => setState(() => _accepted = value),
              onAccept: _accept,
              onSignOut: _saving ? null : _signOut,
            ),
          ],
        ),
      ),
    );
  }
}

/// The short version. Not a substitute for the documents — the point is that someone who will not
/// read 8,000 words still learns the three things most likely to surprise them.
class _GateSummary extends StatelessWidget {
  const _GateSummary();

  static const _points = <(IconData, String)>[
    (
      Icons.groups_outlined,
      'Your profile is visible to other signed-in members by default. You can hide it any time.',
    ),
    (
      Icons.lock_outline_rounded,
      'Messages are stored on our servers, not end-to-end encrypted. Administrators only ever see '
          'messages someone reports.',
    ),
    (
      Icons.shield_outlined,
      'Harassment, impersonation, spam and sharing other people’s private details can cost '
          'you your account.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (final (index, (icon, text)) in _points.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: index == _points.length - 1 ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.dmSans(
                        fontSize: 13.5,
                        color: AppColors.textMid,
                        height: 1.45,
                      ),
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

/// Pinned below the scroll region, so the checkbox and both buttons are reachable without
/// scrolling to the end of a long page.
class _GateActions extends StatelessWidget {
  final bool accepted;
  final bool saving;
  final ValueChanged<bool> onChanged;
  final VoidCallback onAccept;
  final VoidCallback? onSignOut;

  const _GateActions({
    required this.accepted,
    required this.saving,
    required this.onChanged,
    required this.onAccept,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final active = accepted && !saving;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Checkbox(
                  value: accepted,
                  onChanged: saving ? null : (value) => onChanged(value ?? false),
                  activeColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  side: const BorderSide(color: AppColors.border, width: 1.5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.textMid,
                      ),
                      children: [
                        const TextSpan(text: 'I agree to the '),
                        ...policyPairSpans(context),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: active ? 1 : 0.45,
            child: GestureDetector(
              onTap: active ? onAccept : null,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF5A94C2), Color(0xFF3E7EB4)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Accept and continue',
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // The way out. The router will not let a user leave this screen any other way, and the
          // onboarding lock taught us what a forced screen with no exit costs.
          Center(
            child: TextButton(
              onPressed: onSignOut,
              style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
              child: Text(
                'Sign out',
                style: GoogleFonts.dmSans(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

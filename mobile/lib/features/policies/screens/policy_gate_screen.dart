import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.xxxl,
                  AppSpacing.xxl,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The LC mark rather than a generic shield: this is the first screen an
                    // existing user sees after an update, and it should look like the app they
                    // already signed in to, not like a compliance interstitial.
                    Row(
                      children: [
                        Image.asset('assets/images/lclogo.webp',
                            width: 34, height: 34, fit: BoxFit.contain),
                        const SizedBox(width: 10),
                        // Flexible, or the wordmark overflows at 320px with text scaled to the
                        // 1.4 the app clamps to — the same trap the login button had.
                        Flexible(
                          child: Text(
                            'LC Connect',
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      'Before you continue',
                      style: AppTypography.display.copyWith(color: AppColors.textDark),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Please read the Terms of Service and Privacy Policy, then accept to '
                      'continue.',
                      style: AppTypography.body.copyWith(color: AppColors.textMuted, height: 1.5),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _GateSummary(),
                    const SizedBox(height: AppSpacing.xxl),
                    const _SectionLabel('Read in full'),
                    const SizedBox(height: AppSpacing.sm),
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

/// Section label in sentence case, like the day labels and group headings elsewhere — not the
/// spaced capitals it used to be.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textMuted),
    );
  }
}

/// Reassurance, deliberately **not** a summary of the policies.
///
/// It used to preview specific clauses here — profile visibility, that messages are not
/// end-to-end encrypted. Putting that on the first screen someone sees turns a welcome into a
/// disclaimer, and it lands as a warning rather than as the context it has in the document, where
/// the reasoning sits next to it. The documents say those things properly; this screen's job is to
/// point at them.
///
/// Every line here must be true and must not overclaim: no "fully secure", no "private", nothing
/// the Privacy Policy would contradict.
class _GateSummary extends StatelessWidget {
  const _GateSummary();

  static const _points = <(IconData, String)>[
    (Icons.school_outlined, 'Built for the Livingstone College campus community.'),
    (Icons.lock_outline_rounded, 'Your information is protected, and we never sell it.'),
    (Icons.tune_rounded, 'Privacy settings you can change at any time.'),
  ];

  @override
  Widget build(BuildContext context) {
    // A soft brand tint, no outline: it is reassurance, not a form to fill in.
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadii.all(AppRadii.sheet),
      ),
      child: Column(
        children: [
          for (final (index, (icon, text)) in _points.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: index == _points.length - 1 ? 0 : AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: AppColors.primaryText),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      text,
                      style: AppTypography.body.copyWith(color: AppColors.textMid, height: 1.45),
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
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.sm,
        AppSpacing.xxl,
        AppSpacing.md + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The whole line toggles, not only the 18dp box. The policy names inside it stay their
          // own links: their recognizers win the tap they sit under.
          InkWell(
            onTap: saving ? null : () => onChanged(!accepted),
            borderRadius: AppRadii.all(AppRadii.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
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
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text.rich(
                        TextSpan(
                          style: AppTypography.bodySmall.copyWith(
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
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The same solid pill as every primary action. Disabled until ticked — visibly not ready,
          // rather than a faded gradient that still looked pressable.
          FilledButton(
            onPressed: (accepted && !saving) ? onAccept : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full)),
              disabledBackgroundColor: saving ? AppColors.primary : null,
            ),
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Accept and continue',
                    style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                  ),
          ),
          // The way out. The router will not let a user leave this screen any other way, and the
          // onboarding lock taught us what a forced screen with no exit costs.
          Center(
            child: TextButton(
              onPressed: onSignOut,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                minimumSize: const Size(48, 48),
              ),
              child: Text(
                'Sign out',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

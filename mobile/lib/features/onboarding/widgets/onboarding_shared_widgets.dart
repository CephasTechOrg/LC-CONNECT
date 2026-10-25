import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';

class OnboardingLabel extends StatelessWidget {
  final String text;
  final bool optional;
  const OnboardingLabel(this.text, {super.key, this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      // The same label as every other form: 13 semibold, dark, with a muted "optional".
      child: Row(
        children: [
          Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Text('optional', style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// How many interests / languages a student may choose.
///
/// Matches `_MAX_SELECTIONS` in `backend/app/features/profiles/schema.py`, which enforces it
/// server-side too. Five is enough to say who you are and few enough that the answers stay
/// meaningful — a profile listing twenty interests tells a reader nothing.
const int kMaxSelections = 5;

class OnboardingChipGrid extends StatelessWidget {
  final List<String> options;
  final List<String>? optionKeys;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  /// When set, unselected chips stop responding once this many are chosen. The limit is shown
  /// rather than enforced silently — a chip that just does nothing reads as a broken app.
  final int? maxSelections;

  /// When set, an "Add your own" chip appears. The seeded list is a starting point, not the whole
  /// vocabulary: the backend creates anything unrecognised on save.
  final ValueChanged<String>? onAddCustom;

  const OnboardingChipGrid({
    super.key,
    required this.options,
    this.optionKeys,
    required this.selected,
    required this.onToggle,
    this.maxSelections,
    this.onAddCustom,
  });

  bool get _atLimit =>
      maxSelections != null && selected.length >= maxSelections!;

  Future<void> _promptForCustom(BuildContext context) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => const _AddYourOwnDialog(),
    );
    if (value != null && value.isNotEmpty) onAddCustom!(value);
  }

  @override
  Widget build(BuildContext context) {
    // Run spacing 0: each chip carries its own 48dp tap target around a 34dp pill, like
    // [AppFilterChip], so the rows already sit apart.
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        ...List.generate(options.length, (i) {
          final key = optionKeys?[i] ?? options[i];
          final isOn = selected.contains(key);
          // At the limit, already-chosen chips stay tappable so you can swap one out; it is only
          // adding a sixth that is blocked.
          final locked = _atLimit && !isOn;
          return Opacity(
            opacity: locked ? 0.4 : 1,
            child: _ChoiceChip(
              label: options[i],
              selected: isOn,
              onTap: locked ? null : () => onToggle(key),
            ),
          );
        }),
        if (onAddCustom != null && !_atLimit)
          _ChoiceChip(
            label: 'Add your own',
            icon: Icons.add_rounded,
            selected: false,
            outlined: true,
            onTap: () => _promptForCustom(context),
          ),
      ],
    );
  }
}

/// One selectable pill — the soft selected state every chip in the app uses (tint, accent text),
/// never a solid fill: a solid chip outranked the Continue button below it.
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// The "Add your own" chip: a brand outline, so it reads as an action rather than an option.
  final bool outlined;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected || outlined;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Align(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySoft : AppColors.surface,
                borderRadius: AppRadii.all(AppRadii.full),
                border: Border.all(
                  color: outlined
                      ? AppColors.primary
                      : selected
                          ? AppColors.primary.withValues(alpha: 0.35)
                          : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: AppColors.primaryText),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
                      color: accent ? AppColors.primaryText : AppColors.textMid,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingBottomBar extends StatelessWidget {
  final int step;
  final int totalSteps;
  final bool isLoading;
  final bool canProceed;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const OnboardingBottomBar({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.isLoading,
    required this.canProceed,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == totalSteps - 1;
    final shape = RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full));
    final text = AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700);
    const size = Size.fromHeight(52);
    // Pills, like every other form's action bar: Back outlined, Continue filled.
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.md + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (step > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: isLoading ? null : onBack,
                style: OutlinedButton.styleFrom(
                  minimumSize: size,
                  shape: shape,
                  foregroundColor: AppColors.textDark,
                  side: const BorderSide(color: AppColors.border, width: 1.5),
                ),
                child: Text('Back', style: text),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: (canProceed && !isLoading) ? onNext : null,
              style: FilledButton.styleFrom(
                minimumSize: size,
                shape: shape,
                disabledBackgroundColor: isLoading ? AppColors.primary : null,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isLast ? 'Finish setup' : 'Continue', style: text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sign-out escape for the onboarding header.
///
/// Onboarding is the one screen the router will not let a verified user leave: any other
/// location redirects straight back to `/onboarding` until `profileCompleted` is true. With no
/// sign-out, a student who signed in on the wrong account, or who simply cannot finish right now
/// (the lookup options failing to load on a cold start, say), had no way out of the app at all
/// short of force-quitting — and reopening landed them right back here.
///
/// Signing out clears the session, which drops `isLoggedIn`, which lets the router send them to
/// `/login`. Confirmed first, since it discards anything typed into the form.
class OnboardingSignOutButton extends ConsumerWidget {
  const OnboardingSignOutButton({super.key});

  Future<void> _confirmAndSignOut(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          'You can finish setting up your profile next time you sign in. '
          'Anything you have typed here will be lost.',
          style: AppTypography.body.copyWith(color: AppColors.textMid, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep setting up'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Sign out',
              // AA red; [AppColors.error] is ~3.8:1 as text on white.
              style: AppTypography.body.copyWith(
                color: const Color(0xFFB91C1C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (leave != true) return;
    await ref.read(authNotifierProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () => _confirmAndSignOut(context, ref),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minimumSize: const Size(48, 48),
      ),
      child: Text(
        'Sign out',
        style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The "add your own" prompt, as a widget so it can own and dispose its controller.
///
/// The controller used to be created in the caller and never disposed — a `ChangeNotifier` leaked
/// once per opening, and this dialog can be opened repeatedly during onboarding. Disposing it in
/// the caller instead is not an option: `showDialog` completes when the route is popped, while the
/// exit animation still has the `TextField` mounted, so an eager dispose throws
/// "A TextEditingController was used after being disposed". Owning it here ties the lifetime to
/// the widget that actually uses it.
class _AddYourOwnDialog extends StatefulWidget {
  const _AddYourOwnDialog();

  @override
  State<_AddYourOwnDialog> createState() => _AddYourOwnDialogState();
}

class _AddYourOwnDialogState extends State<_AddYourOwnDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add your own'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'e.g. Afrobeats', counterText: ''),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

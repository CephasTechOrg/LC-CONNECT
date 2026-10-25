part of '../screens/login_screen.dart';

/// The way to the register screen — an outlined pill under the filled Sign in, so the two read as
/// first and second choice at a glance.
class _CreateAccountButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateAccountButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryText,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full)),
      ),
      child: Text(
        'Create account',
        style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

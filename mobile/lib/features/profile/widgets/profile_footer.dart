part of '../screens/profile_screen.dart';

// ── Edit Profile button ───────────────────────────────────────────
class _EditProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: () => context.push('/profile/edit'),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(
            'Edit Profile',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppErrorState(
      message: "Couldn't load your profile",
      onRetry: onRetry,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_provider.dart';

part '../widgets/profile_header.dart';
part '../widgets/profile_hero.dart';
part '../widgets/profile_info_rows.dart';
part '../widgets/profile_looking_for.dart';
part '../widgets/profile_preferences.dart';
part '../widgets/profile_stats.dart';
part '../widgets/profile_footer.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(
            onRetry: () => ref.invalidate(myProfileNotifierProvider),
          ),
          data: (profile) => _ProfileBody(profile: profile),
        ),
      ),
    );
  }
}

// ── Full scrollable body ──────────────────────────────────────────
class _ProfileBody extends ConsumerStatefulWidget {
  final MyProfile profile;
  const _ProfileBody({required this.profile});

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      await ref.read(myProfileNotifierProvider.notifier).uploadAvatar(
            path: image.path,
            mimeType: image.mimeType ?? 'image/jpeg',
            filename: image.name,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo. Try again.',
                style: GoogleFonts.dmSans()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _Header(ref: ref),
        _HeroSection(
          profile: widget.profile,
          uploading: _uploading,
          onAvatarTap: _pickAndUpload,
        ),
        const SizedBox(height: 8),
        _InfoRows(profile: widget.profile),
        const SizedBox(height: 8),
        _LookingForSection(lookingFor: widget.profile.lookingFor),
        const SizedBox(height: 8),
        _PreferencesCard(profile: widget.profile),
        const SizedBox(height: 8),
        _StatsRow(profile: widget.profile),
        const SizedBox(height: 16),
        _EditProfileButton(),
        const SizedBox(height: 24),
      ],
    );
  }
}

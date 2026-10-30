part of '../screens/blueprint_bond_screen.dart';

/// On-page headshot: the photo itself, not an "uploaded" checkmark.
///
/// The file is private, so every read is a fresh signed URL; the image is cached on disk under the
/// upload-time key from `scholarHeadshotPreviewProvider` instead, in the sign-out-cleared
/// [privateImageCacheProvider]. It no longer downloads again on every visit.
class _HeadshotRow extends ConsumerWidget {
  final bool hasFile;
  final bool uploading;
  final VoidCallback onUpload;
  const _HeadshotRow({
    required this.hasFile,
    required this.uploading,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = hasFile
        ? ref.watch(scholarHeadshotPreviewProvider)
        : const AsyncValue<ScholarHeadshot?>.data(null);
    // `.value`, not `asData?.value`: while the preview revalidates, keep showing the photo we
    // have instead of collapsing to a spinner.
    final headshot = preview.value;
    final loading = uploading || (hasFile && preview.isLoading && headshot == null);

    return Row(
      children: [
        _HeadshotThumb(
          headshot: headshot,
          cacheManager: ref.watch(privateImageCacheProvider),
          loading: loading,
          onTap: uploading ? null : onUpload,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Headshot',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                hasFile ? 'Uploaded' : 'JPG or PNG',
                style: AppTypography.caption.copyWith(
                  color: hasFile ? AppColors.green : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: uploading ? null : onUpload,
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryText),
          child: uploading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(hasFile ? 'Replace' : 'Upload', style: _fileActionStyle),
        ),
      ],
    );
  }
}

class _HeadshotThumb extends StatelessWidget {
  final ScholarHeadshot? headshot;
  final BaseCacheManager cacheManager;
  final bool loading;
  final VoidCallback? onTap;
  const _HeadshotThumb({
    required this.headshot,
    required this.cacheManager,
    required this.loading,
    this.onTap,
  });

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = headshot != null && headshot!.url.isNotEmpty;
    return Semantics(
      button: true,
      label: hasPhoto ? 'Headshot, double tap to replace' : 'Add headshot',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            Container(
              key: const Key('blueprint-headshot'),
              width: _size,
              height: _size,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: loading && !hasPhoto
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : hasPhoto
                      ? CachedNetworkImage(
                          imageUrl: headshot!.url,
                          cacheKey: headshot!.cacheKey,
                          cacheManager: cacheManager,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          memCacheWidth: (_size * MediaQuery.devicePixelRatioOf(context)).round(),
                          fadeInDuration: Duration.zero,
                          placeholder: (_, _) => const _HeadshotFallback(),
                          errorWidget: (_, _, _) => const _HeadshotFallback(),
                        )
                      : const _HeadshotFallback(),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeadshotFallback extends StatelessWidget {
  const _HeadshotFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.primarySoft,
      child: Icon(Icons.person_rounded, size: 32, color: AppColors.primary),
    );
  }
}

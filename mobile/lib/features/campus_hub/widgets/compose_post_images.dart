part of '../screens/compose_campus_post_screen.dart';

String _imageMime(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

class _ComposePostImages extends StatelessWidget {
  final List<CampusPostImage> uploaded;
  final List<XFile> pending;
  final int remaining;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<CampusPostImage> onRemoveUploaded;
  final ValueChanged<int> onRemovePending;

  const _ComposePostImages({
    required this.uploaded,
    required this.pending,
    required this.remaining,
    required this.busy,
    required this.onAdd,
    required this.onRemoveUploaded,
    required this.onRemovePending,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('Photos', optional: true),
        Text(
          remaining <= 0 ? '4 photos attached — cover is first.' : '$remaining of 4 photos remaining. First is the cover.',
          style: AppTypography.label.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < uploaded.length; i++)
                _Thumb(
                  key: ValueKey(uploaded[i].id),
                  isCover: i == 0,
                  onRemove: busy ? null : () => onRemoveUploaded(uploaded[i]),
                  child: CachedNetworkImage(imageUrl: uploaded[i].url, fit: BoxFit.cover),
                ),
              for (var i = 0; i < pending.length; i++)
                _Thumb(
                  key: ValueKey(pending[i].path),
                  isCover: uploaded.isEmpty && i == 0,
                  onRemove: busy ? null : () => onRemovePending(i),
                  child: Image.file(File(pending[i].path), fit: BoxFit.cover),
                ),
              if (remaining > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: busy ? null : onAdd,
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final bool isCover;
  final VoidCallback? onRemove;
  final Widget child;

  const _Thumb({super.key, required this.isCover, required this.onRemove, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 88, height: 88, child: child),
          ),
          if (isCover)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'Cover',
                  style: AppTypography.micro.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

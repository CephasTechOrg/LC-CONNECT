import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/avatar_preview.dart';
import '../models/campus_post.dart';

/// Full-width announcement photos above the body. One image is a single tap-to-preview
/// cover; two or more become a pager. First image is the cover used on Home and the list.
class CampusPostImagePager extends StatefulWidget {
  final List<CampusPostImage> images;
  final String postId;

  const CampusPostImagePager({super.key, required this.images, required this.postId});

  @override
  State<CampusPostImagePager> createState() => _CampusPostImagePagerState();
}

class _CampusPostImagePagerState extends State<CampusPostImagePager> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    if (images.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: images.length == 1
                ? _Photo(image: images.first, postId: widget.postId, index: 0)
                : PageView.builder(
                    itemCount: images.length,
                    onPageChanged: (index) => setState(() => _page = index),
                    itemBuilder: (context, index) => _Photo(
                      image: images[index],
                      postId: widget.postId,
                      index: index,
                    ),
                  ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            '${_page + 1} of ${images.length}',
            key: const ValueKey('campus-post-image-pager'),
            style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _Photo extends StatelessWidget {
  final CampusPostImage image;
  final String postId;
  final int index;

  const _Photo({required this.image, required this.postId, required this.index});

  @override
  Widget build(BuildContext context) {
    final heroTag = 'campus-post:$postId:$index';
    return GestureDetector(
      onTap: () => showAvatarPreview(context, imageUrl: image.url, heroTag: heroTag),
      child: Hero(
        tag: heroTag,
        child: CachedNetworkImage(
          imageUrl: image.url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (_, _) => const ColoredBox(color: AppColors.primarySoft),
          errorWidget: (_, _, _) => const ColoredBox(
            color: AppColors.primarySoft,
            child: Icon(Icons.broken_image_outlined, color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

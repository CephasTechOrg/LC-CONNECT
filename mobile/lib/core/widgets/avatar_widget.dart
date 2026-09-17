import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A circular avatar, backed by a disk cache.
///
/// Beta report #17: "revisiting the profile can cause the same unchanged profile image to appear
/// to reload repeatedly". Two causes, both here:
///
/// 1. `Image.network` caches only decoded frames **in RAM**. That cache is wiped on every app
///    restart and under memory pressure, so the same avatar was re-downloaded constantly. The
///    backend was never at fault — avatar URLs are content-versioned with `?v=<upload-ts>` and are
///    perfectly cacheable; there was simply no cache to hold them.
/// 2. The loading placeholder was the same grey silhouette used for *no photo at all*, so every
///    load visibly read as "person icon → face", which is what made it look like a reload rather
///    than a first paint.
class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final double size;

  /// Optional stable id (e.g. userId). Only affects the widget key — the image cache is keyed by
  /// URL, so this cannot cause two users to share a picture.
  final String? cacheScope;

  const AvatarWidget({
    super.key,
    this.imageUrl,
    this.size = 50.0,
    this.cacheScope,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: hasImage
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              key: ValueKey('${cacheScope ?? ''}|$imageUrl'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              // Decode at display size rather than full resolution: an avatar rendered at 28px
              // does not need a 512px bitmap resident for every row of a list.
              memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (context, url) => const _LoadingTint(),
              errorWidget: (context, url, error) => _FallbackIcon(size: size),
            )
          : _FallbackIcon(size: size),
    );
  }
}

/// Shown while an image loads. Deliberately *not* [_FallbackIcon]: a silhouette means "this
/// person has no photo", and using it as a spinner is what made every load look like a reload.
class _LoadingTint extends StatelessWidget {
  const _LoadingTint();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final double size;
  const _FallbackIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primarySoft,
            AppColors.primaryPale,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: size * 0.55,
          color: AppColors.primary.withAlpha(200),
        ),
      ),
    );
  }
}

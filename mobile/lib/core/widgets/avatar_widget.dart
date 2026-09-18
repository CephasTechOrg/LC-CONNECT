import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'avatar_preview.dart';

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

  /// Opens the photo full-screen when tapped (report #3).
  ///
  /// Off by default, and that is the design rather than caution: most avatars in this app sit in
  /// a row whose tap already navigates to the person, and hijacking that would break the primary
  /// action. Pass a tag only where the avatar is large and its tap is otherwise unused — see
  /// [showAvatarPreview] for the three places this is deliberately withheld.
  ///
  /// The tag must be a stable identity (`avatar:<userId>`), not the URL, which changes when the
  /// photo does.
  final String? previewHeroTag;

  /// Name for the preview's semantics label, so a screen reader says whose photo it is.
  final String? previewName;

  const AvatarWidget({
    super.key,
    this.imageUrl,
    this.size = 50.0,
    this.cacheScope,
    this.previewHeroTag,
    this.previewName,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    // No preview without a photo: a viewer showing the fallback silhouette full-screen offers
    // nothing, and an avatar that opens *sometimes* is worse than one that never does.
    final canPreview = hasImage && previewHeroTag != null;

    final avatar = Container(
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

    if (!canPreview) return avatar;
    return Semantics(
      button: true,
      label: previewName == null
          ? 'Profile photo, double tap to view'
          : "$previewName's profile photo, double tap to view",
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => showAvatarPreview(
          context,
          imageUrl: imageUrl!,
          heroTag: previewHeroTag!,
          name: previewName,
        ),
        // The Hero on this side of the flight. Both ends need the same tag, and only one of each
        // tag may be on screen at a time — which is why this is opt-in per call site rather than
        // switched on for every avatar.
        child: Hero(tag: previewHeroTag!, child: avatar),
      ),
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

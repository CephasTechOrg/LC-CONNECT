import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final double size;
  /// Optional stable id (e.g. userId) so avatars never share Flutter's image cache.
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
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: hasImage
          ? Image.network(
              imageUrl!,
              // ValueKey (+ the backend's ?v=<ts> avatar URLs) busts the cache on update;
              // Image.network keys its ImageProvider cache by URL, so scopes don't collide.
              key: ValueKey('${cacheScope ?? ''}|$imageUrl'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) => _FallbackIcon(size: size),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _FallbackIcon(size: size);
              },
            )
          : _FallbackIcon(size: size),
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

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const AvatarWidget({
    super.key,
    this.imageUrl,
    this.size = 50.0,
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

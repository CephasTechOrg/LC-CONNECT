import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../models/campus_post.dart';

/// Compact (list) or expanded (detail) preview for an opportunity `externalUrl`.
///
/// Uses server-stored [LinkPreview] when present; otherwise falls back to the
/// URL hostname so the card still looks clickable.
class LinkPreviewCard extends StatelessWidget {
  final String url;
  final LinkPreview? preview;
  final bool compact;
  final VoidCallback? onTap;

  const LinkPreviewCard({
    super.key,
    required this.url,
    this.preview,
    this.compact = true,
    this.onTap,
  });

  String get _domain {
    final fromPreview = preview?.domain?.trim();
    if (fromPreview != null && fromPreview.isNotEmpty) return fromPreview;
    return linkPreviewHost(url) ?? 'Link';
  }

  String get _title {
    final t = preview?.title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final site = preview?.siteName?.trim();
    if (site != null && site.isNotEmpty) return site;
    return _domain;
  }

  String? get _description {
    final d = preview?.description?.trim();
    if (d == null || d.isEmpty) return null;
    return d;
  }

  String? get _imageUrl {
    final u = preview?.imageUrl?.trim();
    if (u == null || u.isEmpty) return null;
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final child = compact ? _buildCompact() : _buildExpanded();
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        child: child,
      ),
    );
  }

  Widget _buildCompact() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Thumb(imageUrl: _imageUrl, size: 40, radius: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.textMuted),
        ],
      ),
    );
  }

  Widget _buildExpanded() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_imageUrl != null)
            AspectRatio(
              aspectRatio: 1.91,
              child: Image.network(
                _imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ImageFallback(tall: true),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_imageUrl == null) ...[
                      const _Thumb(imageUrl: null, size: 36, radius: 8),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        _domain.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.textMuted),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    height: 1.25,
                  ),
                ),
                if (_description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.textMid,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final double radius;

  const _Thumb({required this.imageUrl, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl == null
            ? const _ImageFallback()
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ImageFallback(),
              ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  final bool tall;

  const _ImageFallback({this.tall = false});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primarySoft,
      child: Center(
        child: Icon(
          Icons.link_rounded,
          size: tall ? 28 : 18,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

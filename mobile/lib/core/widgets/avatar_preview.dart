import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Opens [imageUrl] full-screen, zoomable and dismissible (report #3).
///
/// [heroTag] must match the tag on the avatar that opened it, so the photo grows out of its own
/// thumbnail rather than appearing from nowhere. Use a stable identity — `avatar:<userId>` — not
/// the URL, which changes whenever the photo is replaced.
///
/// ## Where this is deliberately *not* offered
///
/// Report #3 asked for photo viewing, and the instinct is to attach it to every avatar. Three
/// places where that would be wrong:
///
///  * **Dense list rows** — the inbox, the directory, member lists. Tapping a row must keep
///    navigating to the person; opening an image instead would break the primary action.
///  * **Your own profile.** That tap already opens the image picker to *change* your photo, which
///    is the more useful action and is advertised by the camera badge on the avatar.
///  * **Scholar headshots.** They live in a private bucket behind 300-second signed URLs. Routing
///    one through a viewer would put an expiring credential into a widget that outlives it — and
///    into the image cache. They do not use [AvatarWidget] at all, which keeps them out of reach
///    of this by construction rather than by remembering.
Future<void> showAvatarPreview(
  BuildContext context, {
  required String imageUrl,
  required String heroTag,
  String? name,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      // Transparent so the Hero flies over the page underneath rather than over a blank screen.
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      // The label a screen reader announces on the barrier.
      barrierLabel: 'Close photo',
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, _) => _AvatarPreview(
        imageUrl: imageUrl,
        heroTag: heroTag,
        name: name,
      ),
      transitionsBuilder: (context, animation, _, child) {
        // Reduced motion gets no fade — the Hero itself is handled by Flutter, which already
        // honours the setting.
        if (MediaQuery.disableAnimationsOf(context)) return child;
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.imageUrl, required this.heroTag, this.name});

  final String imageUrl;
  final String heroTag;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final label = name == null ? 'Profile photo' : "$name's profile photo";

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tapping anywhere outside the photo closes it, which is what people try first.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Center(
            child: Semantics(
              image: true,
              label: label,
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    // No decode cap here, unlike the thumbnail: this is the one place the full
                    // resolution is the point.
                    placeholder: (context, url) => const SizedBox(
                      height: 64,
                      width: 64,
                      child: Center(child: CircularProgressIndicator(color: Colors.white54)),
                    ),
                    errorWidget: (context, url, error) => const Padding(
                      padding: EdgeInsets.all(AppSpacing.xxl),
                      child: Text(
                        "Couldn't load this photo.",
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // A real close button as well as the tap-anywhere and the system back gesture: the
          // other two are discoverable only by trying them.
          Positioned(
            top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
            right: AppSpacing.sm,
            child: Semantics(
              button: true,
              label: 'Close photo',
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                // 48dp, the minimum target — the default IconButton is 40.
                iconSize: 28,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

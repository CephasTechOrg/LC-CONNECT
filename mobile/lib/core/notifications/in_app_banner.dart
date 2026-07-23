import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';

/// One in-app banner's content.
class BannerData {
  final String conversationId;
  final String title; // sender name (or "New message")
  final String body; // message preview
  final String? avatarUrl;

  const BannerData({
    required this.conversationId,
    required this.title,
    required this.body,
    this.avatarUrl,
  });
}

/// Holds the currently-visible banner (or null). Single source; the host just renders it.
final currentBannerProvider =
    NotifierProvider<CurrentBannerNotifier, BannerData?>(CurrentBannerNotifier.new);

class CurrentBannerNotifier extends Notifier<BannerData?> {
  Timer? _autoDismiss;

  @override
  BannerData? build() {
    ref.onDispose(() => _autoDismiss?.cancel());
    return null;
  }

  /// Show a banner; a newer message replaces the current one and resets the timer
  /// (banners never stack).
  void show(BannerData data) {
    _autoDismiss?.cancel();
    state = data;
    _autoDismiss = Timer(const Duration(seconds: 4), dismiss);
  }

  void dismiss() {
    _autoDismiss?.cancel();
    state = null;
  }
}

/// Floating banner host. Mounted once (in MaterialApp.builder's Stack) so it sits above
/// every route. Renders nothing when there's no active banner.
class InAppBannerHost extends ConsumerWidget {
  const InAppBannerHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = ref.watch(currentBannerProvider);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => SlideTransition(
          position: Tween(begin: const Offset(0, -1), end: Offset.zero).animate(anim),
          child: child,
        ),
        child: banner == null
            ? const SizedBox.shrink()
            : _BannerCard(
                key: ValueKey('${banner.conversationId}|${banner.body}'),
                data: banner,
              ),
      ),
    );
  }
}

class _BannerCard extends ConsumerWidget {
  final BannerData data;
  const _BannerCard({super.key, required this.data});

  void _open(WidgetRef ref) {
    ref.read(currentBannerProvider.notifier).dismiss();
    ref.read(routerProvider).push('/messages/${data.conversationId}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Dismissible(
          key: ValueKey('dismiss-${data.conversationId}-${data.body}'),
          direction: DismissDirection.up,
          onDismissed: (_) => ref.read(currentBannerProvider.notifier).dismiss(),
          child: Material(
            color: AppColors.surface,
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            shadowColor: Colors.black26,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    AvatarWidget(imageUrl: data.avatarUrl, size: 40, cacheScope: data.conversationId),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              color: AppColors.textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

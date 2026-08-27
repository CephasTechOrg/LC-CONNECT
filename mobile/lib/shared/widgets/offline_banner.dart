import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/health_provider.dart';
import '../../core/notifications/in_app_banner.dart';
import '../../core/theme/app_theme.dart';

/// App-wide chrome: offline strip (when needed) + floating in-app message banners.
///
/// When offline, the strip consumes the status-bar inset so route [SafeArea]/s
/// don't leave a double gap under the banner.
class AppConnectivityChrome extends ConsumerWidget {
  const AppConnectivityChrome({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(backendStatusProvider) == BackendStatus.offline;
    final mq = MediaQuery.of(context);
    final bodyMedia = offline
        ? mq.copyWith(padding: mq.padding.copyWith(top: 0))
        : mq;

    return Column(
      children: [
        const OfflineBannerHost(),
        Expanded(
          child: MediaQuery(
            data: bodyMedia,
            child: Stack(
              children: [
                ?child,
                const InAppBannerHost(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Global strip shown when the API is unreachable.
class OfflineBannerHost extends ConsumerWidget {
  const OfflineBannerHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backendStatusProvider);
    final visible = status == BackendStatus.offline;

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: visible ? 1 : 0,
        child: visible
            ? const _OfflineStrip()
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }
}

class _OfflineStrip extends ConsumerWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Material(
      color: const Color(0xFF1F2937),
      child: Semantics(
        liveRegion: true,
        label: 'No connection. LC Connect cannot reach the server.',
        child: InkWell(
          onTap: () => ref.read(backendStatusProvider.notifier).checkNow(),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, topInset > 0 ? topInset + 6 : 10, 16, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: Color(0xFFE5E7EB),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'You\'re offline',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Changes will sync when you\'re back online',
                        style: GoogleFonts.dmSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFFD1D5DB),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Retry',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

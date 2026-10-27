import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../data/message_urls.dart';
import '../providers/link_preview_provider.dart';

Future<void> openHttpUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Underlined, tappable URLs inside a bubble. Recognizers live on State so they are disposed
/// instead of leaking (a `TextSpan` recognizer created in `build` never is).
class LinkedMessageText extends StatefulWidget {
  final String text;
  final bool isMine;
  const LinkedMessageText({super.key, required this.text, required this.isMine});

  @override
  State<LinkedMessageText> createState() => _LinkedMessageTextState();
}

class _LinkedMessageTextState extends State<LinkedMessageText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final color = widget.isMine ? Colors.white : AppColors.textDark;
    final linkColor = widget.isMine ? Colors.white : AppColors.primaryText;
    final runs = splitMessageLinks(widget.text);
    return Text.rich(
      TextSpan(
        children: [
          for (final run in runs)
            if (run.isUrl)
              TextSpan(
                text: run.text,
                style: AppTypography.body.copyWith(
                  color: linkColor,
                  height: 1.4,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                recognizer: _tapToOpen(run.text),
              )
            else
              TextSpan(
                text: run.text,
                style: AppTypography.body.copyWith(color: color, height: 1.4),
              ),
        ],
      ),
    );
  }

  TapGestureRecognizer _tapToOpen(String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => openHttpUrl(url);
    _recognizers.add(recognizer);
    return recognizer;
  }
}

/// Compact OG card under a bubble (or above the composer). Falls back to the hostname when
/// unfurl fails or is still in flight, so a pasted link is never a dead rectangle.
class MessageLinkCard extends ConsumerWidget {
  final String url;
  final bool isMine;
  final bool compact;
  const MessageLinkCard({
    super.key,
    required this.url,
    required this.isMine,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(messageLinkPreviewProvider(url));
    final preview = async.value;
    final host = preview?.domain?.trim().isNotEmpty == true
        ? preview!.domain!
        : (Uri.tryParse(url)?.host ?? 'Link');
    final title = () {
      final t = preview?.title?.trim();
      if (t != null && t.isNotEmpty) return t;
      final site = preview?.siteName?.trim();
      if (site != null && site.isNotEmpty) return site;
      return host;
    }();
    final imageUrl = preview?.imageUrl?.trim();
    final onDark = isMine && !compact;
    final fg = onDark ? Colors.white : AppColors.textDark;
    final muted = onDark ? Colors.white70 : AppColors.textMuted;
    final fill = onDark ? Colors.white.withValues(alpha: 0.12) : AppColors.background;
    final border = onDark ? Colors.white24 : AppColors.border;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => openHttpUrl(url),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              _LinkThumb(imageUrl: imageUrl, onDark: onDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, size: 16, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkThumb extends StatelessWidget {
  final String? imageUrl;
  final bool onDark;
  const _LinkThumb({required this.imageUrl, required this.onDark});

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: onDark ? Colors.white12 : AppColors.primarySoft,
      child: Icon(
        Icons.link_rounded,
        size: 18,
        color: onDark ? Colors.white70 : AppColors.primary,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: imageUrl == null || imageUrl!.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

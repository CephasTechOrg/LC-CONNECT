import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// Server-unfurled Open Graph card for a chat URL. Same shape as campus-post previews.
class MessageLinkPreview {
  const MessageLinkPreview({
    required this.url,
    this.domain,
    this.siteName,
    this.title,
    this.description,
    this.imageUrl,
    required this.status,
  });

  final String url;
  final String? domain;
  final String? siteName;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String status; // ok | failed

  bool get isOk => status == 'ok';

  factory MessageLinkPreview.fromJson(Map<String, dynamic> j) => MessageLinkPreview(
        url: j['url'] as String? ?? '',
        domain: j['domain'] as String?,
        siteName: j['site_name'] as String?,
        title: j['title'] as String?,
        description: j['description'] as String?,
        imageUrl: j['image_url'] as String?,
        status: j['status'] as String? ?? 'failed',
      );
}

/// Cached per URL. A failed unfurl is still a value (hostname card), not an error — only a
/// transport failure surfaces as [AsyncError], so the bubble can fall back locally.
final messageLinkPreviewProvider =
    FutureProvider.autoDispose.family<MessageLinkPreview, String>((ref, url) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.post('/messages/link-preview', data: {'url': url});
  return MessageLinkPreview.fromJson(response.data as Map<String, dynamic>);
});

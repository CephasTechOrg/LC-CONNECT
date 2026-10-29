import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../../shared/util/caching.dart';
import '../data/message_search.dart';

/// Messages containing the query, across every chat I am in (protocol 6). Empty for a query under
/// two characters, on an older server, or on any error — the inbox still filters chats by name.
final messageSearchProvider =
    FutureProvider.autoDispose.family<List<MessageSearchHit>, String>((ref, query) async {
  if (query.trim().length < 2) return const [];
  if (!ref.read(realtimeClientProvider).supportsProtocol(kInboxProtocolVersion)) return const [];
  // Typing back and forth over the same prefix reuses the earlier answer.
  cacheFor(ref, const Duration(minutes: 1));
  try {
    final response = await ref
        .read(apiClientProvider)
        .dio
        .get('/messages/search', queryParameters: {'q': query.trim(), 'limit': 20});
    return [
      for (final row in response.data as List) MessageSearchHit.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  } catch (_) {
    return const [];
  }
});

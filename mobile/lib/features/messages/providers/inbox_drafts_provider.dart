import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_draft_store.dart';
import 'messages_provider.dart';

/// Unsent drafts for the chats in the inbox, by addressing id — the "Draft: …" line, as in
/// WhatsApp. Reloaded when a draft is saved or cleared, so leaving a chat updates its row.
final inboxDraftsProvider = FutureProvider<Map<String, String>>((ref) async {
  final store = ref.watch(chatDraftStoreProvider);
  void reload() => ref.invalidateSelf();
  store.changes.addListener(reload);
  ref.onDispose(() => store.changes.removeListener(reload));
  final ids = ref.watch(
    threadsNotifierProvider.select((s) => [for (final t in s.value ?? const []) t.addressingId].join(',')),
  );
  if (ids.isEmpty) return const {};
  return store.loadMany(ids.split(','));
});

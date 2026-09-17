import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../auth/providers/auth_provider.dart';

/// Acknowledges receipt of incoming messages, so their senders get a delivered tick
/// (report #21). Watch once at the app root.
///
/// ## Why here and not in the chat screen
///
/// The chat screen already sends `messages.read` on open and on every arrival, and read implies
/// delivered — so while a conversation is open, a delivery acknowledgement adds nothing. The
/// state worth reporting is the other one: a message arrived, this device has it, and the user
/// has *not* opened the conversation. The chat screen is not mounted then. `conversation.updated`
/// is published to every participant's user channel, so this listener sees the message wherever
/// the user happens to be, which is exactly the claim a delivered tick makes.
///
/// ## Why it is separate from the in-app banner listener
///
/// They read the same event and suppress on almost opposite grounds. The banner is suppressed
/// when the user is already looking at the conversation, is on the Messages list, or has the app
/// backgrounded. **None of those suppress a delivery acknowledgement** — the device has the
/// message in every one of them. Folding this into that listener would have meant its early
/// returns silently deciding delivery too.
final deliveryAckProvider = Provider<void>((ref) {
  final client = ref.watch(realtimeClientProvider);

  final sub = client.events.listen((event) {
    if (event is! ConversationUpdated) return;

    final senderId = event.message['sender_id'] as String?;
    final myId = ref.read(authNotifierProvider).asData?.value?.id;
    // My own message needs no acknowledgement from me, and acknowledging it would make my own
    // messages appear delivered the instant I sent them.
    if (senderId == null || myId == null || senderId == myId) return;

    final messageId = event.message['id'] as String?;
    if (messageId == null) return;

    // Returns false against a protocol 1 server, where nothing understands the frame. Nothing to
    // do about that here: the sender simply keeps one tick, which understates progress rather
    // than claiming something untrue.
    client.markDelivered(event.conversationId, messageId);
  });

  ref.onDispose(sub.cancel);
});

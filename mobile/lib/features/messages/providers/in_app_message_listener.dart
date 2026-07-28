import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/in_app_banner.dart';
import '../../../core/notifications/notification_sound.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import 'messages_provider.dart';
import 'unread_provider.dart';

/// Watches live messages and pops an in-app banner + chime for a message you'd
/// otherwise miss. Watch this once at the app root to keep it alive.
///
/// Suppressed when: the message is your own · you're already in that chat
/// (`activeConversationId`) · you're on the Messages list (the row updates live) ·
/// the app is backgrounded (push handles that case).
final inAppMessageListenerProvider = Provider<void>((ref) {
  final client = ref.watch(realtimeClientProvider);

  final sub = client.events.listen((event) {
    if (event is! ConversationUpdated) return;

    final senderId = event.message['sender_id'] as String?;
    final myId = ref.read(authNotifierProvider).asData?.value?.id;
    if (senderId == null || senderId == myId) return; // ignore my own

    if (event.conversationId == ref.read(unreadProvider).activeConversationId) {
      return; // already reading this chat
    }

    // Background is push's job, not the banner's. (null = pre-first-event → treat as active.)
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

    if (_currentPath(ref) == '/messages') return; // on the list → row already updates

    final partner = _partnerFor(ref, event.conversationId);
    ref.read(currentBannerProvider.notifier).show(BannerData(
          conversationId: event.conversationId,
          title: partner?.displayName ?? 'New message',
          body: event.message['body'] as String? ?? '',
          avatarUrl: partner?.avatarUrl,
        ));
    ref.read(notificationSoundProvider).play();
  });

  ref.onDispose(sub.cancel);
});

String _currentPath(Ref ref) {
  // Defensive: before the Router is attached, reading the config can throw. Failing
  // open (empty path) just means we show the banner rather than crash.
  try {
    return ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
  } catch (_) {
    return '';
  }
}

MessagePartner? _partnerFor(Ref ref, String conversationId) {
  final threads = ref.read(threadsNotifierProvider).asData?.value;
  if (threads == null) return null;
  for (final t in threads) {
    // Match on the addressing id (match id for a DM, conversation id for a staff thread) —
    // the same id the server puts in the event frame.
    if (t.addressingId == conversationId) return t.partner;
  }
  return null;
}

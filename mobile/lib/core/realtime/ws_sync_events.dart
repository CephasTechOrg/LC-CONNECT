part of 'ws_protocol.dart';

// Protocol 5 frames that keep presence, mute and notifications in step across devices.

/// A DM partner came online or went offline (protocol 5). [visible] false means they hid their
/// status — show nothing.
class PresenceEvent extends InboundEvent {
  final String userId;
  final bool online;
  final String? lastSeenAt;
  final bool visible;
  const PresenceEvent(this.userId, {required this.online, this.lastSeenAt, this.visible = true});
}

/// This user muted or unmuted a chat, possibly on another device (protocol 5).
class ConversationMuted extends InboundEvent {
  final String conversationId;
  final bool muted;
  const ConversationMuted(this.conversationId, this.muted);
}

/// An unread notification was withdrawn (its reaction was taken back) (protocol 5).
class NotificationRetracted extends InboundEvent {
  final String id;
  const NotificationRetracted(this.id);
}

/// These notifications were read elsewhere — another device, or by opening their chat (protocol 5).
class NotificationsRead extends InboundEvent {
  final List<String> ids;
  const NotificationsRead(this.ids);
}

/// Pure Dart mirror of the backend WebSocket wire protocol
/// (see backend `app/features/realtime/protocol.py`). No I/O — unit-testable.
library;

/// What this client can speak. What the *server* speaks is a separate question — see
/// `RealtimeClient.supportsProtocol`, and gate every frame added after v1 on it.
///
/// 2 adds `messages.delivered` (outbound) and `messages.delivery` (inbound).
/// 3 adds `messages.reaction` and `message.edited` (both inbound). Reactions and edits are
/// *applied* over REST, not as frames: each needs a response an optimistic change can be rolled
/// back from, and an edit additionally needs the 409 that says the window has passed.
const int kProtocolVersion = 3;

/// Frames introduced in protocol 2. Pass to `RealtimeClient.supportsProtocol` before sending one.
const int kDeliveryProtocolVersion = 2;

/// Reactions arrived in protocol 3. Nothing is *sent* over the socket for them, so this gates the
/// affordance rather than a frame: a server below this has no `/reactions` endpoint either, and
/// offering a control that 404s is worse than not offering it.
const int kReactionProtocolVersion = 3;

/// Editing arrived alongside reactions, in the same protocol 3. Gated separately from
/// [kReactionProtocolVersion] despite the equal value: they are independent capabilities, and a
/// later version that moves one without the other would otherwise silently take the other with it.
const int kMessageEditProtocolVersion = 3;

// ── Outbound frames (client → server) ─────────────────────────────────────────

Map<String, dynamic> authFrame(String accessToken, {String? deviceId, String? appVersion}) => {
      'type': 'auth',
      'access_token': accessToken,
      'device_id': ?deviceId,
      'app_version': ?appVersion,
      'protocol_version': kProtocolVersion,
    };

Map<String, dynamic> subscribeFrame(String requestId, String conversationId) => {
      'type': 'conversation.subscribe',
      'request_id': requestId,
      'conversation_id': conversationId,
    };

Map<String, dynamic> unsubscribeFrame(String conversationId) => {
      'type': 'conversation.unsubscribe',
      'conversation_id': conversationId,
    };

Map<String, dynamic> sendFrame({
  required String requestId,
  required String conversationId,
  required String clientMessageId,
  required String body,
}) => {
      'type': 'message.send',
      'request_id': requestId,
      'conversation_id': conversationId,
      'client_message_id': clientMessageId,
      'body': body,
    };

Map<String, dynamic> typingFrame(String conversationId, {required bool active}) => {
      'type': active ? 'typing.start' : 'typing.stop',
      'conversation_id': conversationId,
    };

Map<String, dynamic> readFrame(String conversationId, String throughMessageId) => {
      'type': 'messages.read',
      'conversation_id': conversationId,
      'through_message_id': throughMessageId,
    };

/// "My device has everything up to `throughMessageId`" (protocol 2).
///
/// Symmetric with [readFrame] and, like it, a monotonic boundary rather than a per-message flag:
/// re-sending one is a no-op server-side, which is what makes it safe to re-send after a
/// reconnect. Deliberately sent by the client and never inferred by the server — a write to a
/// half-open socket succeeds while nothing arrives, so only the receiving end can attest to
/// delivery.
Map<String, dynamic> deliveredFrame(String conversationId, String throughMessageId) => {
      'type': 'messages.delivered',
      'conversation_id': conversationId,
      'through_message_id': throughMessageId,
    };

/// Application-level keepalive. The server's idle reaper only sees inbound *application*
/// frames, so transport pings cannot keep the socket alive — a chat left open without typing
/// is closed at `WS_IDLE_TIMEOUT_SECONDS` and stops receiving.
Map<String, dynamic> pingFrame() => {'type': 'ping'};

// ── Inbound events (server → client) ──────────────────────────────────────────

sealed class InboundEvent {
  const InboundEvent();
}

class AuthOk extends InboundEvent {
  final String userId;
  final int heartbeatSeconds;
  final int protocolVersion;
  const AuthOk(this.userId, this.heartbeatSeconds, this.protocolVersion);
}

class MessageAck extends InboundEvent {
  final String? clientMessageId;
  final bool duplicate;
  final Map<String, dynamic> message;
  const MessageAck(this.clientMessageId, this.duplicate, this.message);
}

class MessageCreated extends InboundEvent {
  final String conversationId;
  final Map<String, dynamic> message;
  const MessageCreated(this.conversationId, this.message);
}

class ConversationUpdated extends InboundEvent {
  final String conversationId;
  final Map<String, dynamic> message;
  const ConversationUpdated(this.conversationId, this.message);
}

class TypingEvent extends InboundEvent {
  final String conversationId;
  final String userId;
  final bool active;
  const TypingEvent(this.conversationId, this.userId, this.active);
}

class ReadReceipt extends InboundEvent {
  final String conversationId;
  final String userId;
  final String throughMessageId;
  final String readAt;
  const ReadReceipt(this.conversationId, this.userId, this.throughMessageId, this.readAt);
}

/// Someone else's device now has everything up to [throughMessageId] (protocol 2).
///
/// The sender renders this as the second tick. Honour the boundary rather than flipping every
/// message — the same mistake `markMineRead` makes with [ReadReceipt] today, which is invisible
/// with one tick state and visibly wrong with two.
class DeliveryReceipt extends InboundEvent {
  final String conversationId;
  final String userId;
  final String throughMessageId;
  final String deliveredAt;
  const DeliveryReceipt(
      this.conversationId, this.userId, this.throughMessageId, this.deliveredAt);
}

/// Someone's reaction on a message changed (protocol 3).
///
/// Carries the resulting state ([added]) rather than a delta, so an add racing a remove resolves
/// to last-write-wins — the same answer the database gives, which keeps a client from disagreeing
/// with the server about whether a chip is filled.
class ReactionEvent extends InboundEvent {
  final String messageId;
  final String userId;
  final String emoji;
  final bool added;
  const ReactionEvent(this.messageId, this.userId, this.emoji, this.added);
}

/// A message's body changed (protocol 3).
///
/// Carries the new body rather than a diff: a client may not hold the original — paged out, or
/// the edit arrived on another device — and a diff it cannot apply is useless.
class MessageEdited extends InboundEvent {
  final String conversationId;
  final String messageId;
  final String body;
  final String editedAt;
  const MessageEdited(this.conversationId, this.messageId, this.body, this.editedAt);
}

class NotificationEvent extends InboundEvent {
  /// The serialized notification (id, type, group, actor, ...) — same shape as `GET /notifications`.
  final Map<String, dynamic> notification;
  const NotificationEvent(this.notification);
}

class MessageDeleted extends InboundEvent {
  final String conversationId;
  final String messageId;
  const MessageDeleted(this.conversationId, this.messageId);
}

/// Campus-wide ping that a new announcement went live. Content-free — carries only the audience
/// ('all' | 'students' | 'staff') so the client bumps its counter only when it applies.
class AnnouncementEvent extends InboundEvent {
  final String audience;
  const AnnouncementEvent(this.audience);
}

/// Campus-wide ping that a new opportunity went live. Same content-free shape as announcements —
/// bumps the Opportunities hub badge, not Latest Updates.
class OpportunityEvent extends InboundEvent {
  final String audience;
  const OpportunityEvent(this.audience);
}

/// Reply to [pingFrame]. Its arrival is what proves the socket is still two-way — a half-open
/// TCP connection accepts writes silently, so silence here is the only detectable symptom.
class Pong extends InboundEvent {
  const Pong();
}

class WsError extends InboundEvent {
  final String code;
  final String message;

  /// The `request_id` of the frame that caused this error, when the server could attribute it.
  /// Null for connection-wide errors (idle timeout, revocation). Without it a single error
  /// cannot be told apart from a blanket failure, so callers must not fail unrelated work.
  final String? requestId;
  const WsError(this.code, this.message, {this.requestId});
}

class UnknownEvent extends InboundEvent {
  final String type;
  const UnknownEvent(this.type);
}

InboundEvent parseInbound(Map<String, dynamic> raw) {
  final type = raw['type'] as String?;
  switch (type) {
    case 'auth.ok':
      return AuthOk(
        raw['user_id'] as String,
        (raw['heartbeat_interval_seconds'] as num?)?.toInt() ?? 25,
        (raw['protocol_version'] as num?)?.toInt() ?? 1,
      );
    case 'message.ack':
      return MessageAck(
        raw['client_message_id'] as String?,
        raw['duplicate'] as bool? ?? false,
        Map<String, dynamic>.from(raw['message'] as Map),
      );
    case 'message.created':
      return MessageCreated(raw['conversation_id'] as String, Map<String, dynamic>.from(raw['message'] as Map));
    case 'conversation.updated':
      return ConversationUpdated(raw['conversation_id'] as String, Map<String, dynamic>.from(raw['message'] as Map));
    case 'typing':
      return TypingEvent(raw['conversation_id'] as String, raw['user_id'] as String, raw['active'] as bool? ?? true);
    case 'messages.receipt':
      return ReadReceipt(
        raw['conversation_id'] as String,
        raw['user_id'] as String,
        raw['through_message_id'] as String,
        raw['read_at'] as String,
      );
    case 'messages.delivery':
      return DeliveryReceipt(
        raw['conversation_id'] as String,
        raw['user_id'] as String,
        raw['through_message_id'] as String,
        raw['delivered_at'] as String,
      );
    case 'message.edited':
      return MessageEdited(
        raw['conversation_id'] as String,
        raw['message_id'] as String,
        raw['body'] as String,
        raw['edited_at'] as String? ?? '',
      );
    case 'messages.reaction':
      return ReactionEvent(
        raw['message_id'] as String,
        raw['user_id'] as String,
        raw['emoji'] as String,
        raw['added'] as bool? ?? true,
      );
    case 'notification':
      return NotificationEvent(Map<String, dynamic>.from(raw['notification'] as Map));
    case 'announcement':
      return AnnouncementEvent(raw['audience'] as String? ?? 'all');
    case 'opportunity':
      return OpportunityEvent(raw['audience'] as String? ?? 'all');
    case 'message.deleted':
      return MessageDeleted(raw['conversation_id'] as String, raw['message_id'] as String);
    case 'pong':
      return const Pong();
    case 'error':
      return WsError(
        raw['code'] as String? ?? 'error',
        raw['message'] as String? ?? '',
        requestId: raw['request_id'] as String?,
      );
    default:
      return UnknownEvent(type ?? 'unknown');
  }
}

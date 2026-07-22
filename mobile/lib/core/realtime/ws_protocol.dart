/// Pure Dart mirror of the backend WebSocket wire protocol
/// (see backend `app/features/realtime/protocol.py`). No I/O — unit-testable.
library;

// ── Outbound frames (client → server) ─────────────────────────────────────────

Map<String, dynamic> authFrame(String accessToken, {String? deviceId, String? appVersion}) => {
      'type': 'auth',
      'access_token': accessToken,
      'device_id': ?deviceId,
      'app_version': ?appVersion,
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

// ── Inbound events (server → client) ──────────────────────────────────────────

sealed class InboundEvent {
  const InboundEvent();
}

class AuthOk extends InboundEvent {
  final String userId;
  final int heartbeatSeconds;
  const AuthOk(this.userId, this.heartbeatSeconds);
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

class WsError extends InboundEvent {
  final String code;
  final String message;
  const WsError(this.code, this.message);
}

class UnknownEvent extends InboundEvent {
  final String type;
  const UnknownEvent(this.type);
}

InboundEvent parseInbound(Map<String, dynamic> raw) {
  final type = raw['type'] as String?;
  switch (type) {
    case 'auth.ok':
      return AuthOk(raw['user_id'] as String, (raw['heartbeat_interval_seconds'] as num?)?.toInt() ?? 25);
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
    case 'error':
      return WsError(raw['code'] as String? ?? 'error', raw['message'] as String? ?? '');
    default:
      return UnknownEvent(type ?? 'unknown');
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/util/app_date_format.dart';
import '../providers/messages_provider.dart';

/// What an outgoing message's progress looks like to its sender.
///
/// Derived rather than stored: [MessageStatus] describes the *send attempt*, while delivery and
/// read are separate facts. Adding `delivered` and `read` as enum cases would put them in the
/// same field as `failed`, which they can coexist with — a message can be delivered and then
/// have a retry fail.
enum OutgoingState {
  /// Handed to the outbox or in flight; no acknowledgement yet.
  sending,

  /// The server has it. One tick.
  sent,

  /// The recipient's device has it. Two ticks, muted.
  delivered,

  /// The recipient has opened the conversation past this message. Two ticks, accented.
  read,

  /// The send ladder ran out — WebSocket, then REST, then the 60s deadline.
  failed;

  /// The sender's view of [message].
  ///
  /// Only meaningful for a message the current user sent; a received message has no such state,
  /// which is why this is not a getter on [ChatMessage].
  static OutgoingState of(ChatMessage message) {
    if (message.status == MessageStatus.failed) return OutgoingState.failed;
    if (message.status == MessageStatus.sending) return OutgoingState.sending;
    if (message.readAt != null) return OutgoingState.read;
    if (message.delivered) return OutgoingState.delivered;
    return OutgoingState.sent;
  }
}

/// The tick (or clock, or retry affordance) for an outgoing message.
///
/// One widget for both the chat bubble and the conversation row, because the two showing
/// different things for the same message is the failure that is impossible to explain to a
/// user — and with four states rather than two it becomes likely rather than theoretical.
///
/// ## Why it is bigger and higher-contrast than before
///
/// Report #23: the tick was a 12px icon, and `check` versus `done_all` in *the same colour* was
/// the only difference between sent and read. At 12px one small tick and two small ticks are
/// genuinely hard to tell apart. Delivery adds a third state to the same glyph pair, so the
/// contrast steps have to carry real information: muted → mid → accent, at 14px.
class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final ChatMessage message;

  /// Retry affordance for a failed send. When null, a failure renders as an icon only — which is
  /// what the conversation row wants, since retrying belongs in the conversation itself.
  final void Function(ChatMessage message)? onRetry;

  /// Drops the "Retry" label, for the conversation row where horizontal space is contested.
  final bool compact;

  /// 14, not the 12 this used to be. See the class comment.
  static const double _size = 14;

  @override
  Widget build(BuildContext context) {
    final state = OutgoingState.of(message);
    return Semantics(
      label: semanticsLabelFor(message),
      // The icons differ by shape *and* colour, and both are invisible to a screen reader; the
      // label is the only thing that conveys the state to one.
      excludeSemantics: true,
      child: switch (state) {
        OutgoingState.sending =>
          const Icon(Icons.schedule_rounded, size: _size, color: AppColors.textMuted),
        OutgoingState.failed => _failed(),
        OutgoingState.sent =>
          const Icon(Icons.check_rounded, size: _size, color: AppColors.textMuted),
        OutgoingState.delivered =>
          const Icon(Icons.done_all_rounded, size: _size, color: AppColors.textMid),
        OutgoingState.read =>
          const Icon(Icons.done_all_rounded, size: _size, color: AppColors.primary),
      },
    );
  }

  Widget _failed() {
    const icon = Icon(Icons.error_outline_rounded, size: _size, color: AppColors.error);
    if (compact || onRetry == null) return icon;
    return GestureDetector(
      onTap: () => onRetry!(message),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 3),
          Text(
            'Retry',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// The spoken equivalent of the tick.
  ///
  /// Read and delivered carry their time, because "Read" alone answers a different question from
  /// the one a sender is asking when they check.
  static String semanticsLabelFor(ChatMessage message) => switch (OutgoingState.of(message)) {
        OutgoingState.sending => 'Sending',
        OutgoingState.failed => 'Not sent. Double tap to retry.',
        OutgoingState.sent => 'Sent',
        // No time: delivery has no per-message timestamp to report — see `ChatMessage.delivered`.
        OutgoingState.delivered => 'Delivered',
        OutgoingState.read => 'Read ${AppDateFormat.time(message.readAt!)}',
      };
}

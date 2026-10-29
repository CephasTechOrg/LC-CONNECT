part of '../screens/chat_screen.dart';

/// The chat's per-bubble actions added in protocol 5, provided once above the list instead of
/// threaded through `_ChatScreenBody` → `_MessageList` → `_BubbleTile` as five more parameters.
class _ChatActions extends InheritedWidget {
  const _ChatActions({
    required super.child,
    required this.keyFor,
    required this.quoteSenderName,
    required this.onQuoteTap,
    this.onReply,
    this.onShowReactors,
    this.highlightedId,
    this.unreadDividerBefore,
    this.unreadCount = 0,
  });

  /// Swipe or "Reply"; null when the server cannot take a reply.
  final void Function(ChatMessage message)? onReply;

  /// "Reacted by", optionally filtered to one emoji; null on an older server.
  final void Function(ChatMessage message, {String? emoji})? onShowReactors;
  final void Function(String messageId) onQuoteTap;
  final GlobalKey Function(String messageId) keyFor;
  final String Function(String userId) quoteSenderName;
  final String? highlightedId;

  /// The message the "New messages" divider sits above, and how many were unread on opening.
  final String? unreadDividerBefore;
  final int unreadCount;

  static _ChatActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChatActions>();

  @override
  bool updateShouldNotify(_ChatActions old) =>
      highlightedId != old.highlightedId ||
      unreadDividerBefore != old.unreadDividerBefore ||
      onReply != old.onReply ||
      onShowReactors != old.onShowReactors;
}

/// The quote at the top of a reply bubble: who it quotes and a line of what they said. Tapping it
/// jumps to the original.
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.quote, required this.isMine});

  final ReplyPreview quote;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final actions = _ChatActions.maybeOf(context);
    final name = actions?.quoteSenderName(quote.senderId) ?? quote.senderName ?? 'Member';
    final onBubble = isMine ? Colors.white : AppColors.textDark;
    final muted = isMine ? Colors.white70 : AppColors.textMuted;
    final text = quote.deleted ? 'Original message was deleted' : quote.snippet;
    return Semantics(
      button: true,
      label: 'Reply to $name: $text. Double tap to show the original.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: quote.deleted ? null : () => actions?.onQuoteTap(quote.id),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: isMine ? Colors.white.withValues(alpha: 0.16) : AppColors.background,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border(left: BorderSide(color: isMine ? Colors.white : AppColors.primary, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: onBubble),
              ),
              Text(
                quote.edited && !quote.deleted ? '$text (edited)' : text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: muted,
                  fontStyle: quote.deleted ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar above the composer while replying: who and what you are replying to, with a close
/// button.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.target, required this.name, required this.onCancel});

  final ChatMessage target;
  final String name;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name == 'You' ? 'Replying to yourself' : 'Replying to $name',
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryText),
                ),
                Text(
                  oneLine(target.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMid),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Swipe a bubble right to reply, as in WhatsApp. Drags that start at the very left edge are left
/// alone, so the iOS back swipe still works.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});

  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _trigger = 56.0;
  static const _maxPull = 72.0;
  static const _edgeGuard = 24.0;

  double _dx = 0;
  bool _armed = false;
  bool _ignored = false;

  void _start(DragStartDetails d) {
    _ignored = d.globalPosition.dx < _edgeGuard;
    _armed = false;
  }

  void _update(DragUpdateDetails d) {
    if (_ignored) return;
    final next = (_dx + d.delta.dx).clamp(0.0, _maxPull);
    if (!_armed && next >= _trigger) {
      _armed = true;
      HapticFeedback.lightImpact();
    } else if (_armed && next < _trigger) {
      _armed = false;
    }
    setState(() => _dx = next);
  }

  void _end([DragEndDetails? _]) {
    if (_armed) widget.onReply();
    setState(() {
      _dx = 0;
      _armed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _start,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: (_dx / _trigger).clamp(0.0, 1.0),
            child: const Padding(
              padding: EdgeInsets.only(left: AppSpacing.sm),
              child: Icon(Icons.reply_rounded, color: AppColors.textMuted, size: 22),
            ),
          ),
          AnimatedContainer(
            duration: _dx == 0 ? const Duration(milliseconds: 180) : Duration.zero,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

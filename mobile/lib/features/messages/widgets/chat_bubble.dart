part of '../screens/chat_screen.dart';

class _BubbleTile extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool isGroup;
  final String? partnerAvatarUrl;
  final MessageSender? sender; // group mode: the message's sender identity
  final bool showSenderIdentity; // first message of a sender's run in a group → show name

  /// Where this bubble sits in its run (see `computeMessageRuns`). The avatar and the bubble's
  /// tail anchor to the last message; spacing is tight inside a run and opens up after it.
  final bool firstOfRun;
  final bool lastOfRun;

  /// Timestamp + tick row. Usually the last of a run; the list also sets it where my tick
  /// state changes mid-run. Failed, sending and edited messages show it regardless.
  final bool showFooter;
  final void Function(ChatMessage)? onReport;
  final void Function(ChatMessage)? onDelete; // delete-for-everyone (own message, or I moderate)
  final void Function(ChatMessage)? onRetry;

  /// Null when the connected server predates reactions — see `kReactionProtocolVersion`. Offering
  /// a control whose endpoint 404s is worse than not offering it.
  final void Function(ChatMessage message, String emoji)? onReact;

  /// Null when the server predates editing. Shown only for the sender's own, undeleted messages
  /// that are still inside the window.
  final void Function(ChatMessage)? onEdit;
  const _BubbleTile({
    required this.message,
    required this.isMine,
    this.isGroup = false,
    this.partnerAvatarUrl,
    this.sender,
    this.showSenderIdentity = false,
    this.firstOfRun = true,
    this.lastOfRun = true,
    this.showFooter = true,
    this.onReport,
    this.onDelete,
    this.onReact,
    this.onEdit,
    this.onRetry,
  });

  static const _avatarSize = 28.0;
  static const _bubbleRadius = Radius.circular(18);
  static const _tailRadius = Radius.circular(AppRadii.xs);

  /// Reaction badge geometry. The strip overlaps the bubble's bottom edge and the stack reserves
  /// [_reactionOverhang] below it, so the badge never bleeds into the footer or the next message.
  static const _reactionOverhang = 14.0;
  static const _reactionInset = 10.0;

  bool get _canReport => !isMine && onReport != null;

  /// A deleted message keeps no body, so a reaction on it would hang off a tombstone. An
  /// unsent (`local:`) one has no server id to react to yet.
  bool get _canReact =>
      onReact != null && !message.deleted && !message.id.startsWith('local:');

  /// Sender only, still in the window, not deleted, and actually sent.
  ///
  /// The window check is **advisory** — the server enforces it from its own clock. This just
  /// stops the app offering an action that would come back 409.
  bool get _canEdit =>
      onEdit != null &&
      isMine &&
      !message.deleted &&
      !message.id.startsWith('local:') &&
      DateTime.now().difference(message.createdAt) < kEditWindow;
  bool get _canDelete => onDelete != null;

  /// Only for my own group messages. In a DM the tick already answers this precisely, and for
  /// someone else's message "who has read it" is not mine to ask.
  bool get _canSeeReadBy => isGroup && isMine && !message.deleted && !message.id.startsWith('local:');
  // Copy is always offered on a live message, so the sheet opens even when react/report/delete
  // are not wired (a received DM on an older protocol, for example).
  bool get _hasMenu => !message.deleted;

  bool get _isEdited => message.editedAt != null && !message.deleted;

  /// A short all-emoji message reads better large and bare, as in most chat apps.
  bool get _isBigEmoji => !message.deleted && isEmojiOnly(message.body);

  /// A failed or in-flight send must never hide inside a run — it is the one footer the
  /// sender has to act on (or wait on).
  bool get _footerVisible =>
      showFooter ||
      _isEdited ||
      (isMine &&
          !message.deleted &&
          message.status != MessageStatus.sent);

  bool get _canReplyTo => !message.deleted && !message.id.startsWith('local:');

  @override
  Widget build(BuildContext context) {
    final actions = _ChatActions.maybeOf(context);
    final highlighted = actions?.highlightedId == message.id;
    Widget tile = AnimatedContainer(
      key: actions?.keyFor(message.id),
      duration: const Duration(milliseconds: 250),
      // A brief tint after jumping here from a reply's quote, so the eye lands on it.
      color: highlighted ? AppColors.primarySoft : Colors.transparent,
      padding: EdgeInsets.only(bottom: lastOfRun ? AppSpacing.md : 2),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            _leadingAvatar(context),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showSenderIdentity && sender != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: 2),
                    child: Text(
                      sender!.name,
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                _withReactions(
                  context,
                  GestureDetector(
                  onLongPress: _hasMenu ? () => _showOptions(context) : null,
                  // Double-tap opens the same sheet so reacting does not depend on discovering
                  // long-press alone (Wave A optional affordance).
                  onDoubleTap: _canReact ? () => _showOptions(context) : null,
                  child: _isBigEmoji
                      ? Padding(
                          // Newer color-emoji glyphs can paint wider than their measured advance,
                          // so the text overflows visibly into this inset instead of clipping.
                          padding: EdgeInsets.only(
                            left: isMine ? AppSpacing.lg : 2,
                            right: isMine ? AppSpacing.lg : AppSpacing.sm,
                            top: 2,
                            bottom: 2,
                          ),
                          child: Text(
                            message.body.trim(),
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(fontSize: 30, height: 1.2),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: _bubbleDecoration(),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72,
                          ),
                          child: message.deleted ? _deletedBody() : _textBody(),
                        ),
                ),
                ),
                if (_footerVisible) _footer(),
              ],
            ),
          ),
        ],
      ),
    );
    if (actions?.onReply != null && _canReplyTo) {
      tile = _SwipeToReply(onReply: () => actions!.onReply!(message), child: tile);
    }
    return tile;
  }

  /// Attaches the reaction strip to the bubble's lower, tail-side corner (WhatsApp-style) rather
  /// than as a detached row below. The strip overlaps the bubble by a few px; the stack reserves
  /// [_reactionOverhang] underneath so it never collides with the footer or the next message.
  /// An un-reacted message pays no extra space — it returns the bare bubble.
  Widget _withReactions(BuildContext context, Widget bubble) {
    final reactions = message.deleted ? const <ReactionSummary>[] : message.reactions;
    if (reactions.isEmpty) return bubble;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: _reactionOverhang),
          child: bubble,
        ),
        Positioned(
          bottom: 0,
          // Tail side: bottom-right on my messages, bottom-left on the other person's.
          left: isMine ? null : _reactionInset,
          right: isMine ? _reactionInset : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: _ReactionStrip(
              isMine: isMine,
              reactions: reactions,
              onToggle: _canReact ? (emoji) => onReact!(message, emoji) : (_) {},
              onShowReactors: _ChatActions.maybeOf(context)?.onShowReactors == null
                  ? null
                  : (emoji) => _ChatActions.maybeOf(context)!.onShowReactors!(message, emoji: emoji),
            ),
          ),
        ),
      ],
    );
  }

  /// One avatar per run, on its last bubble — the one the tail points from. Earlier bubbles
  /// keep the gutter so the column stays aligned.
  Widget _leadingAvatar(BuildContext context) {
    if (!lastOfRun) return const SizedBox(width: _avatarSize);
    if (!isGroup) {
      return AvatarWidget(imageUrl: partnerAvatarUrl, size: _avatarSize);
    }
    return GestureDetector(
      // Tap a sender's avatar → their profile.
      onTap: sender?.profileId != null
          ? () => context.push('/users/${sender!.profileId}', extra: sender!.name)
          : null,
      child: AvatarWidget(
        imageUrl: sender?.avatarUrl,
        size: _avatarSize,
        cacheScope: message.senderId,
      ),
    );
  }

  BoxDecoration _bubbleDecoration() {
    final tailed = lastOfRun && !message.deleted;
    return BoxDecoration(
      color: message.deleted
          ? AppColors.background
          // primaryText, not primary, behind the white text of my own messages: the brand blue is
          // 4.3:1 with white, under AA for 14px body text; this shade is 5.1:1.
          : (isMine ? AppColors.primaryText : AppColors.surface),
      borderRadius: BorderRadius.only(
        topLeft: _bubbleRadius,
        topRight: _bubbleRadius,
        bottomLeft: tailed && !isMine ? _tailRadius : _bubbleRadius,
        bottomRight: tailed && isMine ? _tailRadius : _bubbleRadius,
      ),
      border: isMine && !message.deleted ? null : Border.all(color: AppColors.border),
    );
  }

  Widget _deletedBody() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block_rounded, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            'This message was deleted',
            style: AppTypography.bodySmall.copyWith(
              fontStyle: FontStyle.italic,
              color: AppColors.textMuted,
            ),
          ),
        ],
      );

  Widget _textBody() {
    final url = firstHttpUrl(message.body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.replyTo != null) _ReplyQuote(quote: message.replyTo!, isMine: isMine),
        LinkedMessageText(text: message.body, isMine: isMine),
        if (url != null) ...[
          const SizedBox(height: AppSpacing.sm),
          MessageLinkCard(url: url, isMine: isMine),
        ],
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, left: 2, right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('h:mm a').format(message.createdAt.toLocal()),
            style: AppTypography.micro.copyWith(color: AppColors.textMuted),
          ),
          if (_isEdited) ...[
            const SizedBox(width: AppSpacing.xs),
            // Quiet, and never omitted: a conversation where text can change silently
            // is one nobody can rely on.
            Text(
              'edited',
              style: AppTypography.micro.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.textMuted,
              ),
            ),
          ],
          if (isMine && !message.deleted) ...[
            const SizedBox(width: 5),
            // See [MessageStatusIcon] — shared with the conversation row so the two can never
            // show different states for the same message.
            MessageStatusIcon(message: message, onRetry: onRetry),
          ],
        ],
      ),
    );
  }
}

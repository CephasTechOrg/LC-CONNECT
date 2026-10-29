part of '../screens/chat_screen.dart';

/// Reaction UI and its optimistic toggle (report #4).
///
/// Its own `part` file, as the design asked for up front: `chat_bubble.dart` is where the
/// long-press sheet also lives, and it is the file that grows. Editing is in `chat_edit_logic`.
mixin _ChatReactionLogic on _ChatScreenStateBase {
  // Implemented by _ChatScreenLogic, which is mixed in after this one — the same forward
  // declaration _ChatSendLogic already uses.
  void scheduleCacheSave();

  /// Apply a reaction locally, call the server, and settle on its answer.
  ///
  /// Optimistic because a reaction is a *gesture* — the chip must fill under the thumb. One
  /// reaction per person: tapping my current emoji removes it, any other moves my reaction there.
  /// The server's response is the authority (it returns the resulting tallies), so the strip ends
  /// on the server's state rather than on whatever this device guessed.
  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index == -1 || message.id.startsWith('local:')) return;

    final before = messages[index];
    final removing = myEmoji(before.reactions) == emoji;
    setState(() => messages[index] = before.copyWith(reactions: toggleMine(before.reactions, emoji)));
    scheduleCacheSave();
    reactionInFlight.add(message.id);

    try {
      final path = '/messages/${message.id}/reactions/${Uri.encodeComponent(emoji)}';
      final dio = ref.read(apiClientProvider).dio;
      // PUT and DELETE are both idempotent server-side, so a retry or a double-tap needs no
      // special handling here.
      final response = removing ? await dio.delete(path) : await dio.put(path);
      if (disposed || !mounted) return;
      _settle(message.id, response.data);
    } catch (_) {
      if (disposed || !mounted) return;
      // Roll back to exactly what was there, not to "remove the chip": another person's reaction
      // may be in the same chip, and dropping it would delete their tally too.
      final current = messages.indexWhere((m) => m.id == message.id);
      if (current != -1) setState(() => messages[current] = before);
      scheduleCacheSave();
      showReactionFailedSnack();
    } finally {
      reactionInFlight.remove(message.id);
    }
  }

  /// Replace the strip with the server's `ReactionState`, when it sent one (protocol 5; an older
  /// server answers 204 and the optimistic strip stands).
  void _settle(String messageId, Object? data) {
    if (data is! Map || data['reactions'] is! List) return;
    final at = messages.indexWhere((m) => m.id == messageId);
    if (at == -1) return;
    final chips = [
      for (final r in data['reactions'] as List) ReactionSummary.fromJson(Map<String, dynamic>.from(r as Map)),
    ]..sort((a, b) => reactionOrder(a.emoji).compareTo(reactionOrder(b.emoji)));
    setState(() => messages[at] = messages[at].copyWith(reactions: chips));
    scheduleCacheSave();
  }

  /// A live reaction change for a message in this chat.
  ///
  /// Protocol 5 frames carry the resulting state — the tallies and that person's one reaction —
  /// so they are applied as state: a repeated or reordered frame cannot make counts drift. My own
  /// frames count too (they come from my other devices), except while my own request for the same
  /// message is in flight, whose response is the authority. Protocol 3 frames are a +1/−1 delta.
  void applyRemoteReaction(ReactionEvent event) {
    final index = messages.indexWhere((m) => m.id == event.messageId);
    // A reaction for a message that is paged out, or not loaded yet — the next page carries it.
    if (index == -1) return;
    final message = messages[index];
    final fromMe = event.userId == currentUserId;

    if (event.isStateful) {
      if (fromMe && reactionInFlight.contains(event.messageId)) return;
      final mine = fromMe ? event.userEmoji : myEmoji(message.reactions);
      setState(() => messages[index] = message.copyWith(reactions: applyState(event.counts!, mine)));
      scheduleCacheSave();
      return;
    }
    if (fromMe) return; // a v3 frame for my own tap — already applied optimistically
    setState(() => messages[index] = message.copyWith(reactions: _applyDelta(message.reactions, event)));
    scheduleCacheSave();
  }

  List<ReactionSummary> _applyDelta(List<ReactionSummary> before, ReactionEvent event) {
    final chips = [...before];
    final at = chips.indexWhere((r) => r.emoji == event.emoji);
    if (event.added) {
      if (at == -1) {
        chips.add(ReactionSummary(emoji: event.emoji, count: 1, reactedByMe: false));
      } else {
        chips[at] = ReactionSummary(emoji: event.emoji, count: chips[at].count + 1, reactedByMe: chips[at].reactedByMe);
      }
    } else if (at != -1) {
      final remaining = chips[at].count - 1;
      if (remaining <= 0) {
        chips.removeAt(at);
      } else {
        chips[at] = ReactionSummary(emoji: event.emoji, count: remaining, reactedByMe: chips[at].reactedByMe);
      }
    }
    chips.sort((a, b) => reactionOrder(a.emoji).compareTo(reactionOrder(b.emoji)));
    return chips;
  }

  /// "Reacted by" for [message], optionally filtered to one emoji (protocol 5).
  void showReactedBy(ChatMessage message, {String? emoji}) {
    if (!rt.supportsProtocol(kReactorsProtocolVersion)) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReactedBySheet(
        messageId: message.id,
        currentUserId: currentUserId,
        initialEmoji: emoji,
        onRemoveMine: (mine) {
          final current = messages.where((m) => m.id == message.id).firstOrNull;
          if (current != null) toggleReaction(current, mine);
        },
      ),
    );
  }

  void showReactionFailedSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't save that reaction."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// The reaction chips, attached to the bubble's tail-side corner by `_BubbleTile._withReactions`
/// (WhatsApp-style) rather than floating as a detached row. Renders nothing when there are none.
///
/// [isMine] only sets the wrap alignment so a multi-type strip grows away from the tail corner;
/// placement and overlap are the anchor's job.
class _ReactionStrip extends StatelessWidget {
  const _ReactionStrip({
    required this.reactions,
    required this.onToggle,
    this.onShowReactors,
    this.isMine = false,
  });

  final List<ReactionSummary> reactions;
  final void Function(String emoji) onToggle;

  /// Long-press a chip to see who reacted with it; null when the server cannot say.
  final void Function(String emoji)? onShowReactors;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final reaction in reactions)
          _ReactionChip(
            reaction: reaction,
            onTap: () => onToggle(reaction.emoji),
            onLongPress: onShowReactors == null ? null : () => onShowReactors!(reaction.emoji),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, required this.onTap, this.onLongPress});

  final ReactionSummary reaction;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final mine = reaction.reactedByMe;
    return Semantics(
      button: true,
      // Count *and* whether this viewer is in it — a filled outline is the only other signal, and
      // it is colour.
      label: mine
          ? '${reaction.emoji} ${reaction.count}, you reacted. Double tap to remove.'
          : '${reaction.emoji} ${reaction.count}. Double tap to react.',
      onLongPressHint: onLongPress == null ? null : 'see who reacted',
      excludeSemantics: true,
      child: Material(
        color: mine ? AppColors.primarySoft : AppColors.surface,
        // A small lift so the chip reads as sitting on top of the bubble it now overlaps,
        // rather than being painted into it.
        elevation: 1.5,
        shadowColor: Colors.black26,
        shape: StadiumBorder(
          side: BorderSide(color: mine ? AppColors.primary : AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reaction.emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text(
                  '${reaction.count}',
                  style: AppTypography.caption.copyWith(
                    color: mine ? AppColors.primary : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The picker row at the top of the long-press sheet.
class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({required this.chosen, required this.onPick});

  /// The emoji this viewer reacted with, shown as selected (one per person). Picking it again
  /// removes it; picking another moves the reaction.
  final String? chosen;
  final void Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final emoji in kReactionChoices)
            Semantics(
              button: true,
              selected: chosen == emoji,
              label: emoji,
              excludeSemantics: true,
              child: InkResponse(
                onTap: () => onPick(emoji),
                radius: 28,
                child: Container(
                  // 48dp, so the picker is usable rather than a row of tiny targets.
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: chosen == emoji ? AppColors.primarySoft : null,
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

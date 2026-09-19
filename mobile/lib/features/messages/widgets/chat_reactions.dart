part of '../screens/chat_screen.dart';

/// The reactions a user may choose, in picker order. Mirrors `REACTION_ALLOWLIST` server-side,
/// which is the authority — anything else is refused with a 422.
const kReactionChoices = <String>['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Reaction UI and its optimistic toggle (report #4).
///
/// Its own `part` file, as the design asked for up front: `chat_bubble.dart` is where editing and
/// the long-press sheet also live, and it is the file that grows.
/// How long after sending a message may be edited, mirroring `MESSAGE_EDIT_WINDOW_SECONDS`.
///
/// **Advisory only.** The server enforces the real window from its own clock; this exists so the
/// Edit option disappears when it is no longer usable, rather than offering an action that 409s.
/// A client clock that is wrong just means the option lingers or vanishes early — never that an
/// expired edit succeeds.
const kEditWindow = Duration(minutes: 15);

mixin _ChatReactionLogic on _ChatScreenStateBase {
  // Implemented by _ChatScreenLogic, which is mixed in after this one — the same forward
  // declaration _ChatSendLogic already uses.
  void scheduleCacheSave();

  /// Apply a reaction locally, call the server, and put it back if the call fails.
  ///
  /// Optimistic because a reaction is a *gesture* — the chip must fill under the thumb. A
  /// round trip's delay before anything happens reads as a missed tap, and people tap again.
  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index == -1 || message.id.startsWith('local:')) return;

    final before = messages[index];
    final after = _applyToggle(before, emoji);
    final adding = after.reactions.any((r) => r.emoji == emoji && r.reactedByMe);

    setState(() => messages[index] = after);

    try {
      final path = '/messages/${message.id}/reactions/${Uri.encodeComponent(emoji)}';
      final dio = ref.read(apiClientProvider).dio;
      // PUT and DELETE are both idempotent server-side, so a retry or a double-tap needs no
      // special handling here.
      if (adding) {
        await dio.put(path);
      } else {
        await dio.delete(path);
      }
    } catch (_) {
      if (disposed || !mounted) return;
      // Roll back to exactly what was there, not to "remove the chip": another person's reaction
      // may be in the same chip, and dropping it would delete their tally too.
      final current = messages.indexWhere((m) => m.id == message.id);
      if (current != -1) {
        setState(() => messages[current] = before);
      }
      showReactionFailedSnack();
    }
  }

  /// This viewer's toggle applied to [message]'s chip strip.
  ChatMessage _applyToggle(ChatMessage message, String emoji) {
    final chips = [...message.reactions];
    final at = chips.indexWhere((r) => r.emoji == emoji);

    if (at == -1) {
      chips.add(ReactionSummary(emoji: emoji, count: 1, reactedByMe: true));
      // Keep the picker's order, so adding a chip does not reshuffle the strip.
      chips.sort((a, b) =>
          kReactionChoices.indexOf(a.emoji).compareTo(kReactionChoices.indexOf(b.emoji)));
    } else {
      final next = chips[at].toggled();
      if (next == null) {
        chips.removeAt(at);
      } else {
        chips[at] = next;
      }
    }
    return message.copyWith(reactions: chips);
  }

  /// A live reaction from someone else (protocol 3).
  ///
  /// Only their own tally moves: `reactedByMe` is this viewer's state and must survive another
  /// person reacting to the same message with the same emoji.
  void applyRemoteReaction(String messageId, String userId, String emoji, bool added) {
    if (userId == currentUserId) return; // already applied optimistically
    final index = messages.indexWhere((m) => m.id == messageId);
    // A reaction for a message that is paged out, or not loaded yet — the next page carries it.
    if (index == -1) return;

    final message = messages[index];
    final chips = [...message.reactions];
    final at = chips.indexWhere((r) => r.emoji == emoji);

    if (added) {
      if (at == -1) {
        chips.add(ReactionSummary(emoji: emoji, count: 1, reactedByMe: false));
        chips.sort((a, b) =>
            kReactionChoices.indexOf(a.emoji).compareTo(kReactionChoices.indexOf(b.emoji)));
      } else {
        chips[at] = ReactionSummary(
          emoji: emoji,
          count: chips[at].count + 1,
          reactedByMe: chips[at].reactedByMe,
        );
      }
    } else {
      if (at == -1) return;
      final remaining = chips[at].count - 1;
      if (remaining <= 0) {
        chips.removeAt(at);
      } else {
        chips[at] = ReactionSummary(
          emoji: emoji,
          count: remaining,
          reactedByMe: chips[at].reactedByMe,
        );
      }
    }
    setState(() => messages[index] = message.copyWith(reactions: chips));
  }

  /// Replace a message's body, optimistically, rolling back if the server refuses.
  Future<void> editMessage(ChatMessage message, String newBody) async {
    final trimmed = newBody.trim();
    if (trimmed.isEmpty || trimmed == message.body) return;

    final index = messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;
    final before = messages[index];

    setState(() => messages[index] = before.copyWith(body: trimmed, editedAt: DateTime.now()));
    scheduleCacheSave();

    try {
      await ref
          .read(apiClientProvider)
          .dio
          .patch('/messages/${message.id}', data: {'body': trimmed});
    } on DioException catch (e) {
      if (disposed || !mounted) return;
      final at = messages.indexWhere((m) => m.id == message.id);
      if (at != -1) setState(() => messages[at] = before);
      scheduleCacheSave();
      // The server sends a machine-readable reason so this can say which rule was hit rather
      // than a generic failure — the mistake report #8 made with attendance.
      final expired = e.response?.statusCode == 409 &&
          '${(e.response?.data as Map?)?['detail']}' == 'edit_window_expired';
      showEditFailedSnack(
        expired ? 'The edit window has passed.' : "Couldn't save that edit.",
      );
    } catch (_) {
      if (disposed || !mounted) return;
      final at = messages.indexWhere((m) => m.id == message.id);
      if (at != -1) setState(() => messages[at] = before);
      showEditFailedSnack("Couldn't save that edit.");
    }
  }

  /// An edit that arrived from another device, or from the sender while this client is watching.
  void applyRemoteEdit(String messageId, String body, String editedAt) {
    final index = messages.indexWhere((m) => m.id == messageId);
    // Paged out, or not loaded — the next page carries the edited body.
    if (index == -1) return;
    setState(() => messages[index] = messages[index].copyWith(
          body: body,
          editedAt: DateTime.tryParse(editedAt) ?? DateTime.now(),
        ));
    scheduleCacheSave();
  }

  /// Open the edit sheet for [message], then save what comes back.
  ///
  /// A sheet rather than putting the composer into an "edit mode": the composer may already hold
  /// a draft for this conversation, and commandeering it would mean either discarding that draft
  /// or juggling two texts in one field. A sheet leaves the draft untouched.
  Future<void> promptEdit(ChatMessage message) async {
    final edited = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true, // so the keyboard does not cover the field
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
      builder: (_) => _EditMessageSheet(original: message.body, createdAt: message.createdAt),
    );
    if (edited == null || disposed || !mounted) return;
    await editMessage(message, edited);
  }

  void showEditFailedSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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

/// The chips under a bubble. Renders nothing when there are none, so an un-reacted message costs
/// no vertical space.
class _ReactionStrip extends StatelessWidget {
  const _ReactionStrip({required this.reactions, required this.onToggle});

  final List<ReactionSummary> reactions;
  final void Function(String emoji) onToggle;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final reaction in reactions)
            _ReactionChip(reaction: reaction, onTap: () => onToggle(reaction.emoji)),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, required this.onTap});

  final ReactionSummary reaction;
  final VoidCallback onTap;

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
      excludeSemantics: true,
      child: Material(
        color: mine ? AppColors.primarySoft : AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: mine ? AppColors.primary : AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
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

  /// Emoji this viewer has already used on the message, shown as selected.
  final Set<String> chosen;
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
              selected: chosen.contains(emoji),
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
                    color: chosen.contains(emoji) ? AppColors.primarySoft : null,
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


/// The edit composer, shown over the chat.
class _EditMessageSheet extends StatefulWidget {
  const _EditMessageSheet({required this.original, required this.createdAt});

  final String original;
  final DateTime createdAt;

  @override
  State<_EditMessageSheet> createState() => _EditMessageSheetState();
}

class _EditMessageSheetState extends State<_EditMessageSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.original);
  late final Timer _tick;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _recompute();
    // The countdown is advisory — the server decides — but it has to move, or a user typing a
    // long correction has no idea they are about to run out.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _recompute());
  }

  void _recompute() {
    final left = kEditWindow - DateTime.now().difference(widget.createdAt);
    if (!mounted) return;
    setState(() => _remaining = left.isNegative ? Duration.zero : left);
  }

  @override
  void dispose() {
    _tick.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _countdown {
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} left to edit';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining == Duration.zero;
    return Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit message',
                  style: AppTypography.titleSmall.copyWith(color: AppColors.textDark)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                expired ? 'The edit window has passed.' : _countdown,
                style: AppTypography.caption.copyWith(
                  color: expired ? AppColors.error : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 5,
                minLines: 1,
                maxLength: 2000,
                enabled: !expired,
                decoration: const InputDecoration(hintText: 'Your message'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: expired
                        ? null
                        : () => Navigator.of(context).pop(_controller.text.trim()),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

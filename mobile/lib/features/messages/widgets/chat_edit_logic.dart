part of '../screens/chat_screen.dart';

/// How long after sending a message may be edited, mirroring `MESSAGE_EDIT_WINDOW_SECONDS`.
///
/// **Advisory only.** The server enforces the real window from its own clock; this exists so the
/// Edit option disappears when it is no longer usable, rather than offering an action that 409s.
/// A client clock that is wrong just means the option lingers or vanishes early — never that an
/// expired edit succeeds.
const kEditWindow = Duration(minutes: 15);

/// Editing your own message (report #5). Split out of `chat_reactions.dart`, which it shared only
/// for history's sake.
mixin _ChatEditLogic on _ChatScreenStateBase {
  // Implemented by _ChatScreenLogic and _ChatReplyLogic, which are mixed in after this one.
  void scheduleCacheSave();
  void refreshQuotesOf(String messageId, {String? snippet, bool deleted = false});

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
    setState(() {
      messages[index] = messages[index].copyWith(
        body: body,
        editedAt: DateTime.tryParse(editedAt) ?? DateTime.now(),
      );
      refreshQuotesOf(messageId, snippet: oneLine(body));
    });
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
                maxLength: kMaxMessageChars,
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
                    // The app-wide `filledButtonTheme` sets `minimumSize: Size(double.infinity,
                    // 52)` because every other FilledButton here is a full-width form submit.
                    // Inside this Row that demands an infinite width, which is not a cosmetic
                    // overflow: layout throws "BoxConstraints forces an infinite width", and in a
                    // release build the button paints *nothing* — so the sheet offered no way to
                    // save at all. Overridden at the call site rather than in the theme, which
                    // nineteen full-width buttons depend on.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(96, kMinTouchTarget),
                    ),
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

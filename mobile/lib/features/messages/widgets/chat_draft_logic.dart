part of '../screens/chat_screen.dart';

/// Keeps unsent composer text across leaving the conversation, backgrounding, and app restart
/// (report #1).
///
/// The store is plain I/O; the decisions about *when* to write are here, because they are all
/// about the widget's life-cycle:
///
///  * **Debounced on change**, so typing is not one file write per keystroke.
///  * **Flushed on `dispose`**, because leaving the screen is the commonest way to lose a draft
///    and it happens well inside the debounce window.
///  * **Flushed on `paused`**, because `dispose` is not guaranteed to run at all — the OS can
///    reclaim a backgrounded app without ever unwinding the tree, which is exactly the case
///    users notice.
mixin _ChatDraftLogic on _ChatScreenStateBase {
  /// Long enough that ordinary typing coalesces into one write; short enough that a fast
  /// app-switch still lands. The message cache next door uses 400ms for the same reason.
  static const _debounce = Duration(milliseconds: 500);

  Timer? _draftTimer;

  /// Guards against the load racing the user: on a slow first read they may already be typing,
  /// and seeding the field then would overwrite what they just wrote with older text.
  bool _draftLoaded = false;

  /// Captured in [initDraftLogic] rather than read on demand.
  ///
  /// `ref.read` throws during the tree's finalize pass, so reading it inside [flushDraft] made
  /// the flush fail on *every* `dispose` — losing the draft in the commonest case the feature
  /// exists for, and taking the timer cancellation below it down as well. Same reason the unread
  /// notifier is captured in `initState`.
  late final ChatDraftStore _drafts;

  /// The draft's key.
  ///
  /// This is the *addressing* id — the identity the route itself carries, so one route means one
  /// draft. The canonical `conversation_id` would be the more durable key, but it is not known
  /// here on a cold deep link (`thread` is null), and keying on it only when available would give
  /// the same conversation two different keys depending on how the user arrived, which is worse
  /// than a single stable one.
  ///
  /// The trade-off to remember: if DM addressing ever moves from `match_id` to `conversation_id`,
  /// existing drafts need a one-time rename, or they are orphaned and pruned after 30 days.
  String get _draftKey => widget.matchId;

  /// Call from `initState`, before [loadDraft].
  void initDraftLogic() {
    _drafts = ref.read(chatDraftStoreProvider);
  }

  Future<void> loadDraft() async {
    if (!validThread) return;
    final saved = await _drafts.load(_draftKey);
    if (!mounted || disposed) return;
    _draftLoaded = true;
    if (saved == null || inputController.text.isNotEmpty) return;
    inputController
      ..text = saved
      // Cursor at the end, so the user resumes writing rather than inserting at the start.
      ..selection = TextSelection.collapsed(offset: saved.length);
  }

  /// Call from the composer's `onChanged`.
  void onDraftChanged(String text) {
    if (!validThread) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(_debounce, () => _drafts.save(_draftKey, text));
  }

  /// Writes the current text immediately, skipping the pending debounce.
  ///
  /// Not awaited by its callers (`dispose` cannot await, and `paused` must not block the frame),
  /// which is safe because the store swallows its own failures and the write does not depend on
  /// any widget state surviving.
  void flushDraft() {
    if (!validThread || !_draftLoaded) return;
    _draftTimer?.cancel();
    _draftTimer = null;
    _drafts.save(_draftKey, inputController.text);
  }

  /// Call once a message has actually been handed off. The text now lives in the message list,
  /// so keeping it as a draft as well would restore it into the composer on the next visit.
  void clearDraft() {
    _draftTimer?.cancel();
    _drafts.delete(_draftKey);
  }

  void disposeDraftLogic() {
    // Cancelled first: if the flush ever throws again, a pending timer must not outlive the
    // tree — that is a test failure at best and a write against a dead widget at worst.
    _draftTimer?.cancel();
    _draftTimer = null;
    flushDraft();
  }
}

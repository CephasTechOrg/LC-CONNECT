import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/dismiss_keyboard.dart';
import '../../../shared/widgets/verified_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/groups_provider.dart';
import '../../safety/providers/safety_provider.dart';
import '../../safety/widgets/safety_sheet.dart';
import '../providers/messages_provider.dart';
import '../providers/unread_provider.dart';
import '../data/chat_message_cache.dart';

part '../widgets/chat_header.dart';
part '../widgets/chat_message_list.dart';
part '../widgets/chat_bubble.dart';
part '../widgets/chat_input.dart';
part '../widgets/chat_unavailable.dart';
part '../widgets/chat_screen_body.dart';
part '../widgets/chat_send_logic.dart';
part '../widgets/chat_screen_logic.dart';

/// Pixels from the bottom of the list before we treat the user as "scrolled up".
const _kScrollBottomThreshold = 96.0;

class ChatScreen extends ConsumerStatefulWidget {
  /// For a DM this is the match id; for a group it's the group's conversation id — the
  /// backend resolves either. `groupTitle` set ⇒ group mode (no partner card). `groupId`,
  /// when known, lets the header open the group detail/admin screen.
  final String matchId;
  final MessageThread? thread;
  final String? groupTitle;
  final String? groupId;
  final String? groupAvatarUrl;

  const ChatScreen({
    super.key,
    required this.matchId,
    this.thread,
    this.groupTitle,
    this.groupId,
    this.groupAvatarUrl,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

abstract class _ChatScreenStateBase extends ConsumerState<ChatScreen> {
  static const pageSize = 50;

  /// Ceiling on how long to wait for a WebSocket `message.ack` before falling back to HTTP.
  /// Short, because missing it is cheap — it escalates rather than failing.
  ///
  /// This is now only the *upper bound*: [_ChatSendLogic.ackTimeoutFor] shortens it towards
  /// [minAckTimeout] based on recently observed ack latency, so a healthy socket (acks in tens of
  /// milliseconds) does not make a genuinely stuck message sit for six seconds.
  static const ackTimeout = Duration(seconds: 6);

  /// Floor for the adaptive ack wait. Below this a brief scheduling hiccup would start
  /// duplicating work on every send for no benefit.
  static const minAckTimeout = Duration(milliseconds: 1500);

  /// Rolling window of recent ack round-trips, used to size the adaptive wait.
  static const ackSampleSize = 10;

  /// Gap between HTTP retries while the network (or a cold-started server) is unavailable.
  static const restRetryDelay = Duration(seconds: 20);

  /// Total time a message may stay "sending" before it is marked failed. Comfortably longer
  /// than a free-tier cold start, so spin-up latency never shows up as a false failure.
  static const sendDeadline = Duration(seconds: 60);

  final inputController = TextEditingController();
  final scrollController = ScrollController();
  final messages = <ChatMessage>[];
  final seenServerIds = <String>{};

  /// Recent WebSocket ack round-trips, newest last. See [_ChatSendLogic.ackTimeoutFor].
  final ackLatencies = <Duration>[];
  final sendTimers = <String, Timer>{};

  /// When each in-flight send was first attempted, for the `sendDeadline` check.
  final sendStartedAt = <String, DateTime>{};

  bool loading = true;
  bool loadingOlder = false;
  bool hasMore = true;
  String? loadError;
  bool partnerTyping = false;
  String? typingUserId;
  bool awayFromBottom = false;
  int newWhileAway = 0;
  String currentUserId = '';
  DateTime lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  /// Set at the very top of `dispose()`. `mounted` is not sufficient on its own: during unmount
  /// the element is already `defunct` while `State._element` is still set, so `mounted` reads
  /// true and `setState` throws. Stream events buffered before `cancel()` also arrive after
  /// teardown, since cancelling is asynchronous.
  bool disposed = false;

  StreamSubscription<InboundEvent>? eventsSub;
  StreamSubscription<void>? reconnectSub;
  Timer? typingResetTimer;
  Timer? typingStopTimer;
  Timer? cacheSaveTimer;

  late final RealtimeClient rt;
  late final UnreadNotifier unread;

  bool get isGroup => widget.groupId != null;
  bool get validThread => _isValidThreadId(widget.matchId);

  Map<String, MessageSender> senders() {
    if (!isGroup) return const {};
    final members = ref.watch(groupMembersProvider(widget.groupId!)).asData?.value;
    if (members == null) return const {};
    return {
      for (final m in members)
        m.userId: MessageSender(name: m.nameOrFallback, avatarUrl: m.avatarUrl, profileId: m.profileId),
    };
  }
}

class _ChatScreenState extends _ChatScreenStateBase with _ChatSendLogic, _ChatScreenLogic {
  @override
  void initState() {
    super.initState();
    rt = ref.read(realtimeClientProvider);
    currentUserId = ref.read(authNotifierProvider).asData?.value?.id ?? '';
    unread = ref.read(unreadProvider.notifier);
    if (!validThread) {
      loading = false;
      return;
    }
    // Must run after the first frame — Riverpod forbids notifier writes during build.
    Future.microtask(() {
      if (!mounted) return;
      unread.enterConversation(widget.matchId);
      unread.clearConversation(widget.matchId);
      rt.subscribe(widget.matchId);
    });
    eventsSub = rt.events.listen(onEvent);
    reconnectSub = rt.reconnected.listen((_) => syncAfterReconnect());
    scrollController.addListener(onScroll);
    loadInitial();
  }

  @override
  void dispose() {
    disposed = true;
    if (validThread) {
      // Deferred: Riverpod forbids writing to a provider during a widget life-cycle, and
      // `dispose` runs inside the tree's finalize pass. The notifier reference was captured in
      // initState, so it stays valid after this State is gone.
      final unreadNotifier = unread;
      // A microtask, not `Future(...)`: the latter schedules a zero-duration Timer, which
      // `testWidgets` reports as a pending timer and fails the test. Mirrors the
      // `Future.microtask` already used in initState for enterConversation.
      Future.microtask(() => unreadNotifier.leaveConversation());
      rt.unsubscribe(widget.matchId);
    }
    eventsSub?.cancel();
    reconnectSub?.cancel();
    typingResetTimer?.cancel();
    typingStopTimer?.cancel();
    cacheSaveTimer?.cancel();
    for (final t in sendTimers.values) {
      t.cancel();
    }
    inputController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  bool get iAmGroupAdmin {
    if (!isGroup) return false;
    final members = ref.watch(groupMembersProvider(widget.groupId!)).asData?.value;
    if (members == null) return false;
    for (final m in members) {
      if (m.userId == currentUserId) return m.role == 'admin' || m.role == 'owner';
    }
    return false;
  }

  void openDmMenu(MessagePartner partner) {
    showSafetySheet(
      context: context,
      targetUserId: partner.userId,
      targetName: partner.displayName ?? 'this student',
      safetyService: ref.read(safetyServiceProvider),
      onBlocked: () {
        if (mounted) context.go('/messages');
      },
    );
  }

  void reportMessage(ChatMessage message) {
    showReportMessageSheet(
      context: context,
      messageId: message.id,
      groupId: widget.groupId,
      safetyService: ref.read(safetyServiceProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!validThread) return const _UnavailableChat();
    final partner = widget.thread?.partner;

    return _ChatScreenBody(
      partner: partner,
      partnerSubtitle: widget.thread?.partnerSubtitle,
      loading: loading,
      loadError: loadError,
      messages: messages,
      currentUserId: currentUserId,
      isGroup: isGroup,
      groupTitle: widget.groupTitle,
      groupId: widget.groupId,
      groupAvatarUrl: widget.groupAvatarUrl,
      senders: senders(),
      iAmGroupAdmin: iAmGroupAdmin,
      awayFromBottom: awayFromBottom,
      newWhileAway: newWhileAway,
      partnerTyping: partnerTyping,
      typingName: typingName(partner),
      inputController: inputController,
      scrollController: scrollController,
      connectionStatus: rt.status,
      outboxCount: rt.outboxCount,
      onRetryLoad: retryLoadInitial,
      onReport: reportMessage,
      onDelete: deleteMessage,
      onRetry: retry,
      onScrollToBottomTap: scrollToBottomTap,
      onSend: send,
      onTyping: onUserTyping,
      onIdentityTap: isGroup
          ? () => context.push('/groups/${widget.groupId}')
          : (partner != null
              ? () => context.push('/users/${partner.profileId}', extra: partner.displayName)
              : null),
      onMenu: (!isGroup && partner != null) ? () => openDmMenu(partner) : null,
    );
  }
}

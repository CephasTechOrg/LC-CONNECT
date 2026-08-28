part of '../screens/chat_screen.dart';

class _ChatScreenBody extends StatelessWidget {
  final String? partnerSubtitle;
  final MessagePartner? partner;
  final bool loading;
  final String? loadError;
  final List<ChatMessage> messages;
  final String currentUserId;
  final bool isGroup;
  final String? groupTitle;
  final String? groupId;
  final String? groupAvatarUrl;
  final Map<String, MessageSender> senders;
  final bool iAmGroupAdmin;
  final bool awayFromBottom;
  final int newWhileAway;
  final bool partnerTyping;
  final String typingName;
  final TextEditingController inputController;
  final ScrollController scrollController;
  final ValueListenable<RealtimeStatus> connectionStatus;
  final ValueListenable<int> outboxCount;
  final VoidCallback onRetryLoad;
  final void Function(ChatMessage) onReport;
  final void Function(ChatMessage) onDelete;
  final void Function(ChatMessage) onRetry;
  final VoidCallback onScrollToBottomTap;
  final VoidCallback onSend;
  final VoidCallback onTyping;
  final VoidCallback? onIdentityTap;
  final VoidCallback? onMenu;

  const _ChatScreenBody({
    required this.partner,
    this.partnerSubtitle,
    required this.loading,
    required this.loadError,
    required this.messages,
    required this.currentUserId,
    required this.isGroup,
    required this.groupTitle,
    required this.groupId,
    required this.groupAvatarUrl,
    required this.senders,
    required this.iAmGroupAdmin,
    required this.awayFromBottom,
    required this.newWhileAway,
    required this.partnerTyping,
    required this.typingName,
    required this.inputController,
    required this.scrollController,
    required this.connectionStatus,
    required this.outboxCount,
    required this.onRetryLoad,
    required this.onReport,
    required this.onDelete,
    required this.onRetry,
    required this.onScrollToBottomTap,
    required this.onSend,
    required this.onTyping,
    this.onIdentityTap,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(
              title: isGroup ? (groupTitle ?? 'Group') : (partner?.displayName ?? 'Chat'),
              subtitle: isGroup ? null : partnerSubtitle,
              avatarUrl: isGroup ? groupAvatarUrl : partner?.avatarUrl,
              isGroup: isGroup,
              isVerified: !isGroup && (partner?.isVerified ?? false),
              onIdentityTap: onIdentityTap,
              onMenu: onMenu,
            ),
            _ConnectionBanner(status: connectionStatus),
            _OutboxBanner(outboxCount: outboxCount),
            Expanded(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  loading
                      ? const Center(child: CircularProgressIndicator())
                      : loadError != null && messages.isEmpty
                          ? AppErrorState(message: loadError!, onRetry: onRetryLoad)
                          : messages.isEmpty
                              ? _EmptyChatState(name: groupTitle ?? partner?.displayName ?? 'your match')
                              : _MessageList(
                                  messages: messages,
                                  currentUserId: currentUserId,
                                  partnerAvatarUrl: partner?.avatarUrl,
                                  isGroup: isGroup,
                                  senders: senders,
                                  onReport: isGroup ? onReport : null,
                                  onDelete: onDelete,
                                  iAmGroupAdmin: iAmGroupAdmin,
                                  scrollController: scrollController,
                                  onRetry: onRetry,
                                ),
                  if (awayFromBottom && !loading && messages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 8),
                      child: _ScrollToBottomFab(
                        newCount: newWhileAway,
                        onTap: onScrollToBottomTap,
                      ),
                    ),
                ],
              ),
            ),
            if (partnerTyping) _TypingIndicator(name: typingName),
            _InputBar(
              controller: inputController,
              sending: false,
              onSend: onSend,
              onTyping: onTyping,
            ),
          ],
        ),
      ),
    );
  }
}

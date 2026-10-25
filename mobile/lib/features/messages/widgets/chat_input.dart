part of '../screens/chat_screen.dart';

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onTyping;
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onTyping,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attachment (+) removed — media chat is not shipped; a no-op button
          // was a false affordance. Re-add when upload/send-media is implemented.
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                // Truncate at the server's own cap rather than letting the message be typed,
                // sent, and rejected — see [kMaxMessageChars]. A formatter rather than
                // `maxLength` so no character counter appears in the bar.
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kMaxMessageChars),
                ],
                style: AppTypography.body.copyWith(color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Message',
                  hintStyle: AppTypography.body.copyWith(color: AppColors.textMuted),
                  // The app theme gives every field a fill and outline; the pill around this
                  // one already draws both, so all states must opt out explicitly.
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onChanged: (_) => onTyping(),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Two bugs lived here, and together they produced "sometimes tapping send just closes
          // the keyboard instead of sending".
          //
          // 1. `onTap` was `sending ? null : onSend`, and `sending` is true while *any* message
          //    in the thread is still unacknowledged. On a cold backend the first message stays
          //    unacknowledged for up to 60s, so the button was dead for a full minute while the
          //    user tried to send the next one. Disabling it also threw away the point of the
          //    optimistic send path: the outbox queues, the server is idempotent on
          //    `client_message_id`, and `dispatchSend` already reports the one real failure (a
          //    full outbox). There is nothing to protect against by blocking a second send.
          // 2. The target was 40x40, under both Apple's 44pt minimum and this app's own
          //    `kMinTouchTarget`. A near-miss fell through to the app-level
          //    `DismissKeyboardOnTap`, which is why the *keyboard* reacted when the button did
          //    not. The circle draws at 44; the hit area is the full 48.
          //
          // `sending` now drives the spinner only, which is what it was always meant to say.
          // An empty field dims the circle but keeps it tappable, for the same reason.
          Semantics(
            button: true,
            label: 'Send message',
            child: GestureDetector(
              onTap: onSend,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: kMinTouchTarget,
                height: kMinTouchTarget,
                child: Center(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: sending
                              ? AppColors.primarySoft
                              : AppColors.primary.withValues(alpha: hasText ? 1 : 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              )
                            : const Icon(Icons.arrow_upward_rounded,
                                color: Colors.white, size: 22),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Outbox warning ────────────────────────────────────────────────
void _showOutboxFullSnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Send queue is full — wait to reconnect, then tap retry.',
        style: TextStyle(color: Colors.white),
      ),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _OutboxBanner extends StatelessWidget {
  final ValueListenable<int> outboxCount;
  const _OutboxBanner({required this.outboxCount});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: outboxCount,
      builder: (context, count, _) {
        if (count < RealtimeClient.outboxWarnThreshold) return const SizedBox.shrink();
        final full = count >= RealtimeClient.maxOutboxSize;
        final label = full
            ? 'Send queue full — reconnect to send more'
            : 'Send queue nearly full ($count/${RealtimeClient.maxOutboxSize})';
        return _SlimBanner(label: label, color: AppColors.error, icon: Icons.error_outline_rounded);
      },
    );
  }
}

// ── Connection banner ─────────────────────────────────────────────
class _ConnectionBanner extends StatelessWidget {
  final ValueListenable<RealtimeStatus> status;
  const _ConnectionBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RealtimeStatus>(
      valueListenable: status,
      builder: (context, value, _) {
        final (String? label, IconData icon) = switch (value) {
          RealtimeStatus.ready => (null, Icons.wifi_rounded),
          RealtimeStatus.disconnected => ('Offline — reconnecting…', Icons.wifi_off_rounded),
          _ => ('Connecting…', Icons.sync_rounded),
        };
        if (label == null) return const SizedBox.shrink();
        return _SlimBanner(label: label, color: AppColors.textMid, icon: icon);
      },
    );
  }
}

/// A one-line status strip under the header: tinted, icon + label, no border.
class _SlimBanner extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _SlimBanner({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty chat ────────────────────────────────────────────────────
class _EmptyChatState extends StatelessWidget {
  final String name;
  const _EmptyChatState({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadii.sheet),
              ),
              child: const Icon(Icons.waving_hand_rounded, size: 28, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Start the conversation',
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Say hello to $name!',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

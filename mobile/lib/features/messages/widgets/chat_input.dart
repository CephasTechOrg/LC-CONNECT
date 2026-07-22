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
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.textMuted, size: 26),
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 14, color: AppColors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (_) => onTyping(),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: sending ? AppColors.primarySoft : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
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
        final (String? label, Color color) = switch (value) {
          RealtimeStatus.ready => (null, AppColors.primary),
          RealtimeStatus.disconnected => ('Offline — reconnecting…', AppColors.textMuted),
          _ => ('Connecting…', AppColors.textMuted),
        };
        if (label == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: color.withAlpha(30),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        );
      },
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────
class _TypingIndicator extends StatelessWidget {
  final String name;
  const _TypingIndicator({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
      alignment: Alignment.centerLeft,
      child: Text(
        '$name is typing...',
        style: GoogleFonts.dmSans(
          fontSize: 12,
          color: AppColors.textMuted,
          fontStyle: FontStyle.italic,
        ),
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
            const Icon(Icons.waving_hand_rounded,
                size: 48, color: AppColors.border),
            const SizedBox(height: 16),
            Text(
              'Start the conversation',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Say hello to $name!',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

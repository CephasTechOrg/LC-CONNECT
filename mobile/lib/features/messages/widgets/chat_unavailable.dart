part of '../screens/chat_screen.dart';

/// True when `id` is a usable thread id — not empty and not a stringified null. The last line of
/// defence so a malformed id from a deep-link/push can never be sent to the API.
bool _isValidThreadId(String? id) {
  if (id == null) return false;
  final v = id.trim().toLowerCase();
  return v.isNotEmpty && v != 'null' && v != 'undefined';
}

/// Shown instead of the chat when the thread id is missing/malformed — a calm dead-end with a way
/// back, never a red error or a request loop.
class _UnavailableChat extends StatelessWidget {
  const _UnavailableChat();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: Text('Conversation', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, size: 44, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                "This conversation isn't available",
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark),
              ),
              const SizedBox(height: 6),
              Text(
                'It may have been closed or the link was incomplete.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.canPop() ? context.pop() : context.go('/messages'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text('Back to messages', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

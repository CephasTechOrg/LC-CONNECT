part of '../screens/public_profile_screen.dart';

/// The bottom action bar on someone else's profile.
///
/// Extracted so `public_profile_screen.dart` stays under the 600-line hard cap — the screen
/// already splits its staff section the same way.
class _ConnectBar extends StatelessWidget {
  final bool loading;
  final ConnectionStatus state;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  const _ConnectBar({
    required this.loading,
    required this.state,
    required this.onConnect,
    required this.onDisconnect,
  });

  /// Only a stranger gets a live button. Everything else is a status, so the one action that
  /// would fail on the server is never offered in the first place.
  ({String label, IconData icon, bool actionable}) get _display => switch (state) {
        ConnectionStatus.none => (
            label: 'Connect',
            icon: Icons.person_add_alt_1,
            actionable: true,
          ),
        ConnectionStatus.outgoingPending => (
            label: 'Request sent',
            icon: Icons.schedule_rounded,
            actionable: false,
          ),
        ConnectionStatus.incomingPending => (
            label: 'Wants to connect with you',
            icon: Icons.mark_email_unread_outlined,
            actionable: false,
          ),
        ConnectionStatus.connected => (
            label: 'Connected',
            icon: Icons.check_rounded,
            actionable: false,
          ),
        ConnectionStatus.self => (
            label: 'This is you',
            icon: Icons.person_outline_rounded,
            actionable: false,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final display = _display;
    final settled = !display.actionable;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: settled || loading ? null : onConnect,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(display.icon, size: 18),
          label: Text(
            display.label,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: settled ? AppColors.green : AppColors.primary,
            disabledBackgroundColor:
                settled ? AppColors.green : AppColors.primary.withValues(alpha: 0.6),
            disabledForegroundColor: Colors.white,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
          // Only once connected, and deliberately understated: ending a connection should feel
          // like a quiet step back, not a button competing with the rest of the profile.
          if (state == ConnectionStatus.connected)
            TextButton(
              onPressed: onDisconnect,
              style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
              child: Text(
                'Disconnect',
                style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

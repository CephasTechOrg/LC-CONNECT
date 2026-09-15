part of '../screens/campus_hub_screen.dart';

/// Home greeting header: LC mark, personal greeting, and the notification bell.
/// Sits directly on the page background rather than a white bar.
///
/// Two lines on purpose. As one 24px line, "Good afternoon, `<name>`" never fit — the greeting
/// alone overruns the ~250px this column gets on a 393px phone, so the ellipsis always ate the
/// **name**, which is the only part that is actually about the person. Shrinking the type enough
/// to fit would have meant roughly 9px. Splitting it gives the name the full width and the
/// emphasis, and the header stays the same height as before.
class _HomeGreetingHeader extends ConsumerWidget {
  /// "Good afternoon" — no name, no comma.
  final String timeOfDay;

  /// First name, or a fallback derived from the email.
  final String name;

  const _HomeGreetingHeader({required this.timeOfDay, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationCountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          Image.asset(
            'assets/images/lclogo.webp',
            width: 46,
            height: 46,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // scaleDown, not ellipsis: a clipped name is worse than a slightly smaller one,
                // and after the logo and the bell a 320px phone leaves this column ~178px — not
                // enough for a long name at full size. Common names still render at 22px; only
                // the long ones shrink, and none are ever cut.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    timeOfDay,
                    maxLines: 1,
                    style: GoogleFonts.dmSans(
                      fontSize: 13.5,
                      color: AppColors.textMuted,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    maxLines: 1,
                    style: GoogleFonts.dmSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      height: 1.15,
                      letterSpacing: -0.44,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _HomeBell(unread: unread),
        ],
      ),
    );
  }
}

class _HomeBell extends StatelessWidget {
  final int unread;
  const _HomeBell({required this.unread});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: IconButton(
              onPressed: () => context.push('/notifications'),
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.notifications_none_rounded,
                size: 24,
                color: AppColors.textMid,
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

part of '../screens/campus_hub_screen.dart';

/// Home greeting header: LC mark, personal greeting, and the notification bell.
/// Sits directly on the page background rather than a white bar.
class _HomeGreetingHeader extends ConsumerWidget {
  final String greeting;

  const _HomeGreetingHeader({required this.greeting});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationCountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          Image.asset(
            'assets/images/lclogo.png',
            width: 46,
            height: 46,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                    height: 1.1,
                    letterSpacing: -0.48,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Campus Hub · Livingstone College',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 13.5,
                    color: AppColors.textMuted,
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

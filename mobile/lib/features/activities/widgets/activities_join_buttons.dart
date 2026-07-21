part of '../screens/activities_screen.dart';

class _JoinButton extends StatelessWidget {
  final bool joined;
  final bool loading;
  final bool full;
  final VoidCallback onTap;
  const _JoinButton({
    required this.joined,
    required this.loading,
    required this.full,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = joined
        ? AppColors.textMuted
        : full
            ? AppColors.border
            : AppColors.primary;

    return SizedBox(
      height: 36,
      child: Material(
        color: joined ? AppColors.primarySoft : color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: full ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Center(
                    child: Text(
                      joined ? 'Joined' : full ? 'Full' : 'Join',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: joined ? AppColors.primary : Colors.white,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Compact join/leave button (circle icon) ───────────────────────
class _CompactJoinButton extends StatelessWidget {
  final bool joined;
  final bool loading;
  final bool full;
  final VoidCallback onTap;
  const _CompactJoinButton({
    required this.joined,
    required this.loading,
    required this.full,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: full ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: joined
              ? AppColors.primarySoft
              : full
                  ? AppColors.background
                  : AppColors.green,
          shape: BoxShape.circle,
          border: Border.all(
            color: joined
                ? AppColors.primary
                : full
                    ? AppColors.border
                    : AppColors.green,
            width: 1.5,
          ),
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(6),
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppColors.primary),
              )
            : Icon(
                joined ? Icons.check_rounded : Icons.add_rounded,
                size: 16,
                color: joined
                    ? AppColors.primary
                    : full
                        ? AppColors.textMuted
                        : Colors.white,
              ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────

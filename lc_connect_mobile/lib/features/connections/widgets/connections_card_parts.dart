part of '../screens/connections_screen.dart';

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  const _Avatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return AvatarWidget(imageUrl: avatarUrl, size: 52);
  }
}

class _IntentBadge extends StatelessWidget {
  final String intent;
  const _IntentBadge({required this.intent});

  static const _labels = {
    'connect': ('Connect', Icons.people_rounded),
    'study_together': ('Study Together', Icons.menu_book_rounded),
    'language_exchange': ('Language Exchange', Icons.language_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final entry = _labels[intent];
    final label = entry?.$1 ?? intent;
    final icon = entry?.$2 ?? Icons.link_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            'Wants to $label',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool outlined;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.loading,
    required this.outlined,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Material(
        color: outlined ? AppColors.surface : AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: outlined
                ? BoxDecoration(
                    border: Border.all(color: AppColors.border, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            alignment: Alignment.center,
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: outlined ? AppColors.primary : Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          outlined ? AppColors.textDark : Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}


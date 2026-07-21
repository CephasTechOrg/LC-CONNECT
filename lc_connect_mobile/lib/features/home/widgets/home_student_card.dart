part of '../screens/home_screen.dart';

// ── Student cards row ─────────────────────────────────────────────
class _StudentCardsRow extends StatelessWidget {
  final List<DiscoveryCard> cards;
  final bool loading;
  final ValueChanged<DiscoveryCard> onConnect;
  const _StudentCardsRow({
    required this.cards,
    required this.loading,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && cards.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Text(
          'No matches for this category yet.\nTry another or check back later.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...cards.map((card) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _StudentCard(card: card, onConnect: onConnect),
              )),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final DiscoveryCard card;
  final ValueChanged<DiscoveryCard> onConnect;
  const _StudentCard({required this.card, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final tags = card.interests.take(2).toList();
    final sub = _studentSub(card.major, card.classYear);

    return GestureDetector(
      onTap: () => context.push(
        '/users/${card.profileId}',
        extra: card.displayName,
      ),
      child: Container(
        width: 132,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // School background
                Container(
                  height: 90,
                  width: double.infinity,
                  color: AppColors.primaryPale,
                  child: Image.asset(
                    'assets/images/school.png',
                    fit: BoxFit.cover,
                    color: Colors.white.withAlpha(140),
                    colorBlendMode: BlendMode.lighten,
                    opacity: const AlwaysStoppedAnimation(0.45),
                  ),
                ),
                // Avatar overlapping below
                Positioned(
                  bottom: -22,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: AvatarWidget(imageUrl: card.avatarUrl, size: 50),
                    ),
                  ),
                ),
                // Match score badge
                Positioned(
                  bottom: -18,
                  right: 12,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.people_rounded,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  Text(
                    card.displayName ?? 'LC Student',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: tags
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              t,
                              style: GoogleFonts.dmSans(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: SizedBox(
                width: double.infinity,
                child: Material(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => onConnect(card),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Text(
                        'Connect',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

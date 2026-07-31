part of '../screens/home_screen.dart';

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
          'No recommendations yet.\nCheck back soon or explore Connect.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
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
    final tag = card.interests.isNotEmpty ? card.interests.first : null;
    final sub = _studentSub(card.major, card.classYear);

    return GestureDetector(
      onTap: () => context.push(
        '/users/${card.profileId}',
        extra: card.displayName,
      ),
      child: Container(
        width: 152,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D111827),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F111827),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: AvatarWidget(imageUrl: card.avatarUrl, size: 60),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    card.displayName ?? 'LC Student',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                if (card.isVerified) ...[
                  const SizedBox(width: 3),
                  const VerifiedBadge(size: 13),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
            if (tag != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.dmSans(
                    fontSize: 10.5,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => onConnect(card),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_add_alt_1,
                            color: Colors.white, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          'Connect',
                          style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

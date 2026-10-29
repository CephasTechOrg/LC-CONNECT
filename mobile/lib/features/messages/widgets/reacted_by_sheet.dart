part of '../screens/chat_screen.dart';

/// "Reacted by": who reacted to a message and with what — the WhatsApp sheet (protocol 5).
///
/// Opened by long-pressing a reaction chip or from the message's options. Filter chips narrow it
/// to one emoji; my own row reads "You" and removes my reaction when tapped.
class _ReactedBySheet extends ConsumerStatefulWidget {
  const _ReactedBySheet({
    required this.messageId,
    required this.currentUserId,
    this.initialEmoji,
    this.onRemoveMine,
  });

  final String messageId;
  final String currentUserId;
  final String? initialEmoji;

  /// Removes my reaction; null when the server cannot (an older protocol).
  final void Function(String emoji)? onRemoveMine;

  @override
  ConsumerState<_ReactedBySheet> createState() => _ReactedBySheetState();
}

class _ReactedBySheetState extends ConsumerState<_ReactedBySheet> {
  late String? _filter = widget.initialEmoji;

  @override
  Widget build(BuildContext context) {
    final reactors = ref.watch(messageReactorsProvider(widget.messageId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Reactions', style: AppTypography.titleSmall.copyWith(color: AppColors.textDark)),
            const SizedBox(height: 12),
            reactors.cached(
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('No reactions yet.',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
                    )
                  : _content(list),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, _) => Row(
                children: [
                  Expanded(
                    child: Text("Couldn't load reactions.",
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textMid)),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(messageReactorsProvider(widget.messageId)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(List<MessageReactor> all) {
    final counts = <String, int>{};
    for (final r in all) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final emojis = counts.keys.toList()..sort((a, b) => reactionOrder(a).compareTo(reactionOrder(b)));
    final shown = _filter == null ? all : all.where((r) => r.emoji == _filter).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(label: 'All ${all.length}', selected: _filter == null, onTap: () => setState(() => _filter = null)),
              for (final e in emojis)
                _FilterChip(
                  label: '$e ${counts[e]}',
                  selected: _filter == e,
                  onTap: () => setState(() => _filter = e),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shown.length,
            itemBuilder: (context, i) => _reactorRow(shown[i]),
          ),
        ),
      ],
    );
  }

  Widget _reactorRow(MessageReactor r) {
    final mine = r.userId == widget.currentUserId;
    final remove = mine && widget.onRemoveMine != null;
    return InkWell(
      onTap: remove
          ? () {
              Navigator.of(context).pop();
              widget.onRemoveMine!(r.emoji);
            }
          : null,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AvatarWidget(imageUrl: r.avatarUrl, size: 36, cacheScope: r.userId),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mine ? 'You' : r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w500, color: AppColors.textDark),
                  ),
                  if (remove)
                    Text('Tap to remove', style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
            Text(r.emoji, style: const TextStyle(fontSize: 22)),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: AppColors.primarySoft,
        labelStyle: AppTypography.label.copyWith(
          color: selected ? AppColors.primaryText : AppColors.textMid,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        shape: const StadiumBorder(),
      ),
    );
  }
}

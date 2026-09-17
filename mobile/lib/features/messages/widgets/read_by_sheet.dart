part of '../screens/chat_screen.dart';

/// The "read by" list for a group message (report #21).
///
/// Its own `part` file rather than more of `chat_bubble.dart`, which the design doc asked for up
/// front: the bubble is the file reactions and editing also land in, and it is the one that grows.
class _ReadBySheet extends ConsumerWidget {
  const _ReadBySheet({required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readers = ref.watch(messageReadByProvider(messageId));

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
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Read by',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            // `cached` rather than `when`: reopening the sheet inside the cache window shows the
            // list it already has instead of collapsing to a spinner over known data.
            readers.cached(
              data: (list) => list.isEmpty ? const _ReadByEmpty() : _ReadByList(readers: list),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, _) => _ReadByError(
                onRetry: () => ref.invalidate(messageReadByProvider(messageId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadByList extends StatelessWidget {
  const _ReadByList({required this.readers});

  final List<MessageReader> readers;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          // The count is the thing a sender is actually after; without this a screen reader has
          // to walk every row to learn it.
          label: 'Read by ${readers.length} ${readers.length == 1 ? "member" : "members"}',
          child: const SizedBox.shrink(),
        ),
        // Bounded: a large group's list has to scroll rather than push the sheet off-screen.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: readers.length,
            itemBuilder: (context, i) {
              final reader = readers[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    AvatarWidget(
                      imageUrl: reader.avatarUrl,
                      size: 36,
                      // Scoped by user id, not display name — two members sharing a first name
                      // would otherwise share a cache entry.
                      cacheScope: reader.userId,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        reader.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReadByEmpty extends StatelessWidget {
  const _ReadByEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        // Deliberately not "Nobody has read this": the honest reading of an empty list is that
        // nobody has *opened the conversation* past this message yet.
        'No one has caught up to this message yet.',
        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
      ),
    );
  }
}

class _ReadByError extends StatelessWidget {
  const _ReadByError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // Never "no one has read it" — a failed request must not be rendered as a fact
              // about other people.
              "Couldn't load who has read this.",
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMid),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

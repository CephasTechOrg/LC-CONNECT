import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../utils/chat_routes.dart';

/// Which half of the Messages hub is showing.
enum MessagesSegment {
  chats(label: 'Chats', path: messagesPath),
  groups(label: 'Groups', path: groupsPath);

  const MessagesSegment({required this.label, required this.path});

  final String label;
  final String path;
}

/// The `Chats | Groups` switch at the top of the Messages hub.
///
/// Groups used to live as the third segment of the Discovery screen — whose header reads
/// "Connect", which is why testers reported them as being "in Connections" (report #19). Two
/// things were wrong with that home. It was four levels of chrome deep (header, three segments,
/// a search field, a chip row, and *then* the panel's own search field and chips), and Discovery
/// short-circuits any non-student role straight to the staff directory, so **staff could not
/// reach Groups at all** even though the backend deliberately opens groups to them. Messages is
/// not role-gated, so moving them here fixes that as a side effect.
///
/// Each segment is a real route rather than local state, so back behaviour is correct and
/// `/messages/groups` is deep-linkable. The navigation is a `go`, not a `push`: a segment switch
/// replaces its peer rather than stacking on it, so repeated tapping cannot build a pile of
/// alternating Chats and Groups pages for the back button to walk down.
class MessagesSegments extends StatelessWidget {
  const MessagesSegments({super.key, required this.active});

  final MessagesSegment active;

  @override
  Widget build(BuildContext context) {
    const segments = MessagesSegment.values;
    final activeIndex = segments.indexOf(active);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
      child: Semantics(
        container: true,
        label: 'Messages sections',
        // One tinted track with a white thumb under the active label — a single control
        // rather than two separately filled buttons.
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedAlign(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(
                    segments.length == 1 ? 0 : -1 + 2 * activeIndex / (segments.length - 1),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / segments.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final segment in segments)
                    Expanded(
                      child: _Segment(
                        segment: segment,
                        selected: segment == active,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.segment, required this.selected});

  final MessagesSegment segment;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // Which segment is current is otherwise conveyed by fill colour alone, which a screen
      // reader cannot see and a colour-blind user may not distinguish.
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          // Tapping the segment you are already on must not re-navigate; on Chats that would
          // rebuild the thread list for nothing.
          onTap: selected ? null : () => context.go(segment.path),
          borderRadius: BorderRadius.circular(AppRadii.sm),
          // A floor rather than padding arithmetic: this is primary navigation, so it must meet
          // the 44dp minimum target regardless of the font metrics — padding alone landed at 43.
          // A minimum rather than a fixed height so it still grows with the text scale.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  segment.label,
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? AppColors.primary : AppColors.textMid,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

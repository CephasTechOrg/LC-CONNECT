import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Semantics(
        container: true,
        label: 'Messages sections',
        child: Row(
          children: [
            for (final segment in MessagesSegment.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _Segment(
                    segment: segment,
                    selected: segment == active,
                  ),
                ),
              ),
          ],
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
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          // Tapping the segment you are already on must not re-navigate; on Chats that would
          // rebuild the thread list for nothing.
          onTap: selected ? null : () => context.go(segment.path),
          borderRadius: BorderRadius.circular(10),
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
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.textMid,
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

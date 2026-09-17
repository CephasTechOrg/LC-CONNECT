import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../groups/widgets/groups_panel.dart';
import '../widgets/messages_segments.dart';

/// The Groups half of the Messages hub (report #19).
///
/// This is a relocation, not a rewrite: [GroupsPanel] — pending invites, your groups, search,
/// category chips, discovery and Create Group — is unchanged and simply has a new home. What
/// changes is reachability. Its only previous consumer was the third segment of the Discovery
/// screen, which is titled "Connect" and which returns the staff directory outright for any
/// non-student role, so staff had no path to groups whatsoever.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: const [
            // Same title as Chats: the two segments are one destination, and relabelling the
            // header per segment would read as having navigated somewhere else.
            AppShellHeader(title: 'Messages'),
            MessagesSegments(active: MessagesSegment.groups),
            SizedBox(height: 12),
            Expanded(child: GroupsPanel()),
          ],
        ),
      ),
    );
  }
}

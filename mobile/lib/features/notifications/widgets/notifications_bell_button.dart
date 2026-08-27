import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/a11y.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../providers/notifications_provider.dart';

/// Header bell that opens the notification center and shows an unread-count dot.
class NotificationsBellButton extends ConsumerWidget {
  const NotificationsBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(notificationCountProvider);
    final tooltip =
        count > 0 ? 'Notifications, $count unread' : 'Notifications';
    return AppAccessibleIconButton(
      tooltip: tooltip,
      semanticsLabel: tooltip,
      onPressed: () => context.push('/notifications'),
      icon: AppBellIcon(badgeCount: count),
    );
  }
}

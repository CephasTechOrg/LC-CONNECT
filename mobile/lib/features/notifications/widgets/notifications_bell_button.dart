import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/app_shell_header.dart';
import '../providers/notifications_provider.dart';

/// Header bell that opens the notification center and shows an unread-count dot.
class NotificationsBellButton extends ConsumerWidget {
  const NotificationsBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(notificationCountProvider);
    return IconButton(
      onPressed: () => context.push('/notifications'),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: AppBellIcon(badgeCount: count),
    );
  }
}

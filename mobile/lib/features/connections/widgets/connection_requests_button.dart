import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/connections_provider.dart';

/// Connect-header shortcut to `/connections` with an incoming-count badge.
class ConnectionRequestsButton extends ConsumerWidget {
  const ConnectionRequestsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(incomingConnectionCountProvider);
    final icon = Icon(
      Icons.person_add_alt_1_outlined,
      color: AppColors.textDark,
    );
    return IconButton(
      tooltip: count > 0 ? '$count connection requests' : 'Connection requests',
      onPressed: () => context.push('/connections'),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: count > 0
          ? Badge(
              label: Text(count > 99 ? '99+' : '$count'),
              child: icon,
            )
          : icon,
    );
  }
}

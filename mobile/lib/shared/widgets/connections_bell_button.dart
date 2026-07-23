import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/connections/providers/connections_provider.dart';
import 'app_shell_header.dart';

/// Bell that opens connection requests and shows an incoming-count badge.
class ConnectionsBellButton extends ConsumerWidget {
  const ConnectionsBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incomingCount =
        ref.watch(connectionsNotifierProvider).asData?.value.incoming.length ??
            0;
    return IconButton(
      onPressed: () => context.push('/connections'),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: AppBellIcon(badgeCount: incomingCount),
    );
  }
}

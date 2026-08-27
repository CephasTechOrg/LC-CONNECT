import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/connections/providers/connections_provider.dart';
import '../../features/messages/providers/unread_provider.dart';

class NavShell extends ConsumerWidget {
  final Widget child;
  const NavShell({super.key, required this.child});

  // The second tab is student-matching for students, and browsing students for staff — so its
  // label/icon flip by role (the route is the same; the screen renders the right surface).
  static List<_Tab> _tabsFor(bool isStaff) => [
        const _Tab(label: 'Campus', icon: Icons.account_balance_outlined, path: '/home'),
        isStaff
            ? const _Tab(label: 'Students', icon: Icons.school_outlined, path: '/discover')
            : const _Tab(label: 'Connect', icon: Icons.people_outline, path: '/discover'),
        const _Tab(label: 'Activities', icon: Icons.calendar_today_outlined, path: '/activities'),
        const _Tab(label: 'Messages', icon: Icons.message_outlined, path: '/messages'),
        const _Tab(label: 'Profile', icon: Icons.person_outline, path: '/profile'),
      ];

  int _currentIndex(BuildContext context, List<_Tab> tabs) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching here keeps unread + incoming-request mirrors alive across every tab.
    final totalUnread = ref.watch(unreadProvider.select((s) => s.total));
    final incomingRequests = ref.watch(incomingConnectionCountProvider);
    final role = ref.watch(authNotifierProvider).asData?.value?.role ?? 'student';
    final isStaff = role != 'student';
    final tabs = _tabsFor(isStaff);
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Semantics(
          container: true,
          label: 'Main navigation',
          child: BottomNavigationBar(
            currentIndex: _currentIndex(context, tabs),
            onTap: (i) => context.go(tabs[i].path),
            items: tabs
                .map(
                  (t) => BottomNavigationBarItem(
                    icon: _tabIcon(
                      t,
                      totalUnread: totalUnread,
                      incomingRequests: isStaff ? 0 : incomingRequests,
                    ),
                    label: t.label,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _tabIcon(
    _Tab tab, {
    required int totalUnread,
    required int incomingRequests,
  }) {
    Widget icon = Icon(tab.icon);
    String semanticsLabel = tab.label;

    if (tab.path == '/messages' && totalUnread > 0) {
      semanticsLabel = '${tab.label}, $totalUnread unread';
      icon = Badge(
        label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
        child: icon,
      );
    } else if (tab.path == '/discover' &&
        tab.label == 'Connect' &&
        incomingRequests > 0) {
      semanticsLabel = '${tab.label}, $incomingRequests requests';
      icon = Badge(
        label: Text(incomingRequests > 99 ? '99+' : '$incomingRequests'),
        child: icon,
      );
    }

    return Semantics(
      selected: false,
      label: semanticsLabel,
      excludeSemantics: true,
      child: icon,
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final String path;
  const _Tab({required this.label, required this.icon, required this.path});
}

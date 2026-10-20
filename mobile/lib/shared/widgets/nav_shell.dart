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
    const _Tab(
      label: 'Campus',
      icon: Icons.account_balance_outlined,
      activeIcon: Icons.account_balance,
      path: '/home',
    ),
    isStaff
        ? const _Tab(
            label: 'Students',
            icon: Icons.school_outlined,
            activeIcon: Icons.school,
            path: '/discover',
          )
        : const _Tab(
            label: 'Connect',
            icon: Icons.people_outline,
            activeIcon: Icons.people,
            path: '/discover',
          ),
    const _Tab(
      label: 'Activities',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today,
      path: '/activities',
    ),
    const _Tab(
      label: 'Messages',
      icon: Icons.message_outlined,
      activeIcon: Icons.message,
      path: '/messages',
    ),
    const _Tab(
      label: 'Profile',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      path: '/profile',
    ),
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
    final role =
        ref.watch(authNotifierProvider).asData?.value?.role ?? 'student';
    final isStaff = role != 'student';
    final tabs = _tabsFor(isStaff);
    final current = _currentIndex(context, tabs);
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
            currentIndex: current,
            onTap: (i) => context.go(tabs[i].path),
            items: tabs
                .map(
                  (t) => BottomNavigationBarItem(
                    icon: _tabIcon(
                      t,
                      active: false,
                      totalUnread: totalUnread,
                      incomingRequests: isStaff ? 0 : incomingRequests,
                      // This was hardcoded `false`. Review finding #19 read that as "a
                      // screen-reader user is never told which tab is current" — **it is not**:
                      // `BottomNavigationBar` sets the flag itself on the outer "Tab N of M"
                      // node, which is what assistive technology actually reads, and it was
                      // already correct. Passing the real value only stops the inner node from
                      // stating something false.
                      selected: tabs[current].path == t.path,
                    ),
                    activeIcon: _tabIcon(
                      t,
                      active: true,
                      totalUnread: totalUnread,
                      incomingRequests: isStaff ? 0 : incomingRequests,
                      selected: tabs[current].path == t.path,
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
    required bool active,
    required int totalUnread,
    required int incomingRequests,
    required bool selected,
  }) {
    Widget icon = Icon(active ? tab.activeIcon : tab.icon);
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
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: icon,
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
  const _Tab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.path,
  });
}

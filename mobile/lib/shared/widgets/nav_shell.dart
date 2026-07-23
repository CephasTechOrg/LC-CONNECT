import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/messages/providers/unread_provider.dart';

class NavShell extends ConsumerWidget {
  final Widget child;
  const NavShell({super.key, required this.child});

  static const _tabs = [
    _Tab(label: 'Home', icon: Icons.home_outlined, path: '/home'),
    _Tab(label: 'Discover', icon: Icons.search_outlined, path: '/discover'),
    _Tab(label: 'Activities', icon: Icons.calendar_today_outlined, path: '/activities'),
    _Tab(label: 'Messages', icon: Icons.message_outlined, path: '/messages'),
    _Tab(label: 'Profile', icon: Icons.person_outline, path: '/profile'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching here keeps the unread mirror alive across every tab (not just Messages).
    final totalUnread = ref.watch(unreadProvider.select((s) => s.total));
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex(context),
          onTap: (i) => context.go(_tabs[i].path),
          items: _tabs
              .map((t) => BottomNavigationBarItem(
                    icon: _tabIcon(t, totalUnread),
                    label: t.label,
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _tabIcon(_Tab tab, int totalUnread) {
    final icon = Icon(tab.icon);
    if (tab.path != '/messages' || totalUnread <= 0) return icon;
    return Badge(
      label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
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

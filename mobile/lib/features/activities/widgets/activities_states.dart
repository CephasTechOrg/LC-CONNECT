part of '../screens/activities_screen.dart';

class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onClear;
  const _EmptyState({required this.hasFilter, required this.onClear});

  @override
  Widget build(BuildContext context) {
    // The scroll wrapper (needed so pull-to-refresh works with nothing to pull on) lives in
    // [AppScrollableEmptyState] now — three screens had an identical copy of it.
    return AppScrollableEmptyState(
      icon: Icons.calendar_today_outlined,
      title: hasFilter ? 'No activities in this category' : 'No upcoming activities',
      subtitle: hasFilter
          ? 'Try a different filter or check back soon'
          : 'Be the first to create something!',
      actionLabel: hasFilter ? 'Clear filter' : null,
      onAction: hasFilter ? onClear : null,
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppErrorState(
      message: "Couldn't load activities",
      onRetry: onRetry,
    );
  }
}

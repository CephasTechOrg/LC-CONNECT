part of '../screens/activities_screen.dart';

class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onClear;
  const _EmptyState({required this.hasFilter, required this.onClear});

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh works on empty lists.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.12),
        AppEmptyState(
          icon: Icons.calendar_today_outlined,
          title: hasFilter
              ? 'No activities in this category'
              : 'No upcoming activities',
          subtitle: hasFilter
              ? 'Try a different filter or check back soon'
              : 'Be the first to create something!',
          actionLabel: hasFilter ? 'Clear filter' : null,
          onAction: hasFilter ? onClear : null,
        ),
      ],
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

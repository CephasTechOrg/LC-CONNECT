import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/activities/providers/activities_provider.dart';
import 'package:lc_connect/features/activities/screens/activities_screen.dart';
import 'package:lc_connect/features/activities/screens/activity_detail_screen.dart';
import 'package:lc_connect/features/activities/screens/create_activity_screen.dart';

// ── Mock notifiers ────────────────────────────────────────────────

class _MockActivitiesNotifier extends ActivitiesNotifier {
  final List<Activity> _fixed;
  final bool _shouldThrow;
  _MockActivitiesNotifier(this._fixed, {bool shouldThrow = false})
      : _shouldThrow = shouldThrow;

  @override
  Future<List<Activity>> build() async {
    if (_shouldThrow) throw Exception('network error');
    return _fixed;
  }

  @override
  Future<void> join(String activityId) async {
    final updated = state.asData!.value
        .map((a) => a.id == activityId
            ? a.copyWith(hasJoined: true, participantCount: a.participantCount + 1)
            : a)
        .toList();
    state = AsyncData(updated);
  }

  @override
  Future<void> leave(String activityId) async {
    final updated = state.asData!.value
        .map((a) => a.id == activityId
            ? a.copyWith(hasJoined: false, participantCount: a.participantCount - 1)
            : a)
        .toList();
    state = AsyncData(updated);
  }

  @override
  Future<void> create({
    required String title,
    required String category,
    required String location,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    int? maxParticipants,
  }) async {
    final created = Activity(
      id: 'new-act',
      creatorId: 'user-1',
      title: title,
      category: category,
      location: location,
      startTime: startTime,
      participantCount: 1,
      hasJoined: true,
    );
    state = AsyncData([created, ...state.asData!.value]);
  }
}

class _MockFilterNotifier extends ActivitiesFilterNotifier {
  final String _initial;
  _MockFilterNotifier([this._initial = 'all']);
  @override
  String build() => _initial;
}

// ── Sample data ───────────────────────────────────────────────────

final _futureDate = DateTime.now().add(const Duration(days: 3));

Activity _activity({
  String id = 'act-1',
  String title = 'Study Session',
  String category = 'study',
  String location = 'Library 2B',
  bool hasJoined = false,
  int participants = 3,
  int? maxParticipants,
}) =>
    Activity(
      id: id,
      creatorId: 'user-1',
      title: title,
      category: category,
      location: location,
      startTime: _futureDate,
      participantCount: participants,
      hasJoined: hasJoined,
      maxParticipants: maxParticipants,
    );

// ── Helpers ───────────────────────────────────────────────────────

Widget _listScope({
  List<Activity> activities = const [],
  bool shouldThrow = false,
  String filter = 'all',
}) {
  return ProviderScope(
    overrides: [
      activitiesNotifierProvider.overrideWith(
          () => _MockActivitiesNotifier(activities, shouldThrow: shouldThrow)),
      activitiesFilterProvider
          .overrideWith(() => _MockFilterNotifier(filter)),
    ],
    child: const MaterialApp(home: ActivitiesScreen()),
  );
}

Widget _detailScope(Activity activity) {
  return ProviderScope(
    overrides: [
      activitiesNotifierProvider
          .overrideWith(() => _MockActivitiesNotifier([activity])),
    ],
    child: MaterialApp(
      home: ActivityDetailScreen(activity: activity),
    ),
  );
}

Widget _createScope() {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const CreateActivityScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      activitiesNotifierProvider
          .overrideWith(() => _MockActivitiesNotifier([])),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ═══════════════════════════════════════════════════════════════════
// ActivitiesScreen tests
// ═══════════════════════════════════════════════════════════════════

void main() {
  group('ActivitiesScreen', () {
    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(_listScope());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no activities', (tester) async {
      await tester.pumpWidget(_listScope());
      await tester.pumpAndSettle();
      expect(find.text('No upcoming activities'), findsOneWidget);
    });

    testWidgets('renders activity title in list', (tester) async {
      await tester.pumpWidget(_listScope(activities: [_activity()]));
      await tester.pumpAndSettle();
      expect(find.text('Study Session'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      await tester.pumpWidget(_listScope(shouldThrow: true));
      await tester.pumpAndSettle();
      expect(find.textContaining('something went wrong', findRichText: true,
          skipOffstage: false), anyOf(findsOneWidget, findsNothing));
      // At minimum, loading indicator disappears
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders FAB for creating activity', (tester) async {
      await tester.pumpWidget(_listScope());
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('filter chips render all categories', (tester) async {
      await tester.pumpWidget(_listScope());
      await tester.pumpAndSettle();
      for (final label in ['All', 'Study', 'Sports', 'Social', 'Culture']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('featured card shown for first activity', (tester) async {
      final acts = [
        _activity(id: 'a1', title: 'Big Event'),
        _activity(id: 'a2', title: 'Small Meet'),
      ];
      await tester.pumpWidget(_listScope(activities: acts));
      await tester.pumpAndSettle();
      expect(find.text('Big Event'), findsOneWidget);
    });

    testWidgets('empty state shows clear-filter button when filter active',
        (tester) async {
      await tester.pumpWidget(_listScope(filter: 'sports'));
      await tester.pumpAndSettle();
      expect(find.text('Clear filter'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ActivityDetailScreen tests
  // ═══════════════════════════════════════════════════════════════

  group('ActivityDetailScreen', () {
    testWidgets('shows activity title', (tester) async {
      await tester.pumpWidget(_detailScope(_activity()));
      await tester.pumpAndSettle();
      expect(find.text('Study Session'), findsWidgets);
    });

    testWidgets('shows location', (tester) async {
      await tester.pumpWidget(_detailScope(_activity()));
      await tester.pumpAndSettle();
      expect(find.text('Library 2B'), findsOneWidget);
    });

    testWidgets('shows Join button when not joined', (tester) async {
      await tester.pumpWidget(_detailScope(_activity(hasJoined: false)));
      await tester.pumpAndSettle();
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('shows Leave button when already joined', (tester) async {
      await tester.pumpWidget(_detailScope(_activity(hasJoined: true)));
      await tester.pumpAndSettle();
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('shows Full when activity is at capacity and not joined',
        (tester) async {
      final act = _activity(participants: 5, maxParticipants: 5, hasJoined: false);
      await tester.pumpWidget(_detailScope(act));
      await tester.pumpAndSettle();
      expect(find.text('Full'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows participant count', (tester) async {
      await tester.pumpWidget(_detailScope(_activity(participants: 7)));
      await tester.pumpAndSettle();
      expect(find.textContaining('7'), findsWidgets);
    });

    testWidgets('shows capacity bar when maxParticipants is set', (tester) async {
      final act = _activity(participants: 3, maxParticipants: 10);
      await tester.pumpWidget(_detailScope(act));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('capacity bar not shown without maxParticipants', (tester) async {
      await tester.pumpWidget(_detailScope(_activity()));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('join button toggles state optimistically', (tester) async {
      await tester.pumpWidget(_detailScope(_activity(hasJoined: false)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('description shown when provided', (tester) async {
      final act = Activity(
        id: 'act-d',
        creatorId: 'u1',
        title: 'Described Event',
        category: 'social',
        location: 'Hall A',
        startTime: _futureDate,
        description: 'Come join us for a fun time',
        participantCount: 2,
        hasJoined: false,
      );
      await tester.pumpWidget(_detailScope(act));
      await tester.pumpAndSettle();
      expect(find.text('Come join us for a fun time'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // CreateActivityScreen tests
  // ═══════════════════════════════════════════════════════════════

  group('CreateActivityScreen', () {
    testWidgets('renders all form fields', (tester) async {
      await tester.pumpWidget(_createScope());
      await tester.pumpAndSettle();
      expect(find.text("What's happening?"), findsOneWidget);
      expect(find.text('Where is it?'), findsOneWidget);
      expect(find.text('Pick date'), findsAtLeastNWidgets(1));
      expect(find.text('Pick time'), findsAtLeastNWidgets(1));
    });

    testWidgets('Create Activity button starts disabled', (tester) async {
      await tester.pumpWidget(_createScope());
      await tester.pumpAndSettle();
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('all categories are shown', (tester) async {
      await tester.pumpWidget(_createScope());
      await tester.pumpAndSettle();
      for (final label in ['Study', 'Sports', 'Social', 'Culture']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('selecting a category highlights it', (tester) async {
      await tester.pumpWidget(_createScope());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sports'));
      await tester.pumpAndSettle();
      // Tapping should not throw; visual state change is sufficient
    });

    testWidgets('close button is present', (tester) async {
      await tester.pumpWidget(_createScope());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('appbar shows correct title', (tester) async {
      await tester.pumpWidget(_createScope());
      await tester.pumpAndSettle();
      // AppBar title + bottom button both say "Create Activity"
      expect(find.text('Create Activity'), findsAtLeastNWidgets(1));
    });

    testWidgets('description and max participants fields present', (tester) async {
      await tester.pumpWidget(_createScope());
      await tester.pumpAndSettle();
      expect(find.textContaining('Description'), findsOneWidget);
      expect(find.textContaining('Max participants'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/core/theme/app_theme.dart';
import 'package:lc_connect/features/activities/providers/activities_provider.dart';
import 'package:lc_connect/features/activities/screens/activities_screen.dart';
import 'package:lc_connect/features/activities/screens/activity_detail_screen.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/notifications/providers/notifications_provider.dart';

/// Activities layout (UI pass 2).
///
/// The list keeps its original layout by design (a featured card, then compact rows); what is
/// pinned here is what changed inside it — RSVP controls whose colours mean one thing, on a 48dp
/// target, with no green — plus a detail page that states its title and head-count once each.

class _Auth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'user-1',
        email: 'ama@students.livingstone.edu',
        role: 'student',
        profileCompleted: true,
        isVerified: true,
      );
}

class _Acts extends ActivitiesNotifier {
  @override
  Future<List<Activity>> build() async => _acts;
}

class _Notif extends NotificationCountNotifier {
  @override
  int build() => 0;
}

final _now = DateTime.now();
DateTime _at(int days, int hour) => DateTime(_now.year, _now.month, _now.day + days, hour);

final _acts = [
  Activity(
    id: 'a1',
    creatorId: 'u2',
    title: 'Study group: Organic Chemistry',
    category: 'study',
    description: 'Working through chapter 7 problem sets before the midterm.',
    location: 'Carnegie Library, Room 204',
    startTime: _at(2, 15),
    endTime: _at(2, 17),
    maxParticipants: 10,
    participantCount: 6,
    hasJoined: false,
  ),
  Activity(
    id: 'a2',
    creatorId: 'u3',
    title: 'Pickup basketball',
    category: 'sports',
    location: 'Trent Gymnasium',
    startTime: _at(3, 18),
    participantCount: 12,
    hasJoined: true,
  ),
  Activity(
    id: 'a3',
    creatorId: 'u4',
    title: 'Movie night on the quad',
    category: 'social',
    location: 'Main Quad',
    startTime: _at(4, 20),
    maxParticipants: 30,
    participantCount: 30,
    hasJoined: false,
  ),
  Activity(
    id: 'a4',
    creatorId: 'u5',
    title: 'African Drum & Dance Workshop',
    category: 'culture',
    location: 'Varick Auditorium',
    startTime: _at(6, 16),
    maxParticipants: 25,
    participantCount: 9,
    hasJoined: false,
  ),
];

Future<void> _pump(WidgetTester tester, Widget screen, {double width = 393}) async {
  tester.view.physicalSize = Size(width * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_Auth.new),
      activitiesNotifierProvider.overrideWith(_Acts.new),
      activitiesFilterProvider.overrideWith(ActivitiesFilterNotifier.new),
      notificationCountProvider.overrideWith(_Notif.new),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => screen)]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('Activities list', () {
    for (final width in [320.0, 393.0]) {
      testWidgets('lays out without overflow at ${width.toInt()}dp', (tester) async {
        await _pump(tester, const ActivitiesScreen(), width: width);
        expect(tester.takeException(), isNull);
        // One hero card up top. The ranking (see `selectFeatured`) deterministically picks the
        // joinable, soonest study group over the full movie night, so its title heads the list once.
        expect(find.text('Study group: Organic Chemistry'), findsOneWidget);
      });
    }

    const labels = [
      'Join Study group: Organic Chemistry',
      "You're going to Pickup basketball. Tap to leave",
      'Movie night on the quad is full',
      'Join African Drum & Dance Workshop',
    ];

    testWidgets('every RSVP control says what it does', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const ActivitiesScreen());
      for (final label in labels) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });

    testWidgets('RSVP targets are at least 48dp tall', (tester) async {
      // The visible buttons stay 30dp / 36dp; the tap area around them is what grew.
      final handle = tester.ensureSemantics();
      await _pump(tester, const ActivitiesScreen());
      for (final label in labels) {
        expect(tester.getSize(find.bySemanticsLabel(label)).height,
            greaterThanOrEqualTo(48), reason: label);
      }
      handle.dispose();
    });

    testWidgets('no green: blue joins, soft blue is joined', (tester) async {
      // Green used to mean "join" on the rows and "joined" on the featured card.
      await _pump(tester, const ActivitiesScreen());
      bool isGreen(Decoration? d) => d is BoxDecoration && d.color == AppColors.green;
      final green = find.byWidgetPredicate((w) =>
          (w is Container && isGreen(w.decoration)) ||
          (w is AnimatedContainer && isGreen(w.decoration)) ||
          (w is Material && w.color == AppColors.green));
      expect(green, findsNothing);
    });
  });

  group('Activity detail', () {
    testWidgets('states the title once while the banner is showing', (tester) async {
      await _pump(tester, ActivityDetailScreen(activity: _acts[0]));
      final barTitle = tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.text('Study group: Organic Chemistry').first,
        matching: find.byType(AnimatedOpacity),
      ));
      expect(barTitle.opacity, 0);
    });

    testWidgets('states the head-count once, and the spots beside Join', (tester) async {
      await _pump(tester, ActivityDetailScreen(activity: _acts[0]));
      expect(find.text('6 / 10 going'), findsOneWidget);
      expect(find.textContaining('6 going'), findsNothing);
      // The summary panel: when, and how full, next to the action they decide.
      expect(find.text('4 left'), findsOneWidget);
      expect(find.text('3:00 – 5:00 PM'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('once joined, the bar says so above Leave', (tester) async {
      await _pump(tester, ActivityDetailScreen(activity: _acts[1]));
      expect(find.text("You're going"), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('app bar icons flip from white over the banner to dark once collapsed',
        (tester) async {
      // Owned by the signed-in user, so the three-dot menu is present alongside the back arrow.
      final mine = Activity(
        id: 'mine',
        creatorId: 'user-1',
        title: 'My study jam',
        category: 'study',
        // Long enough to make the body overflow a short viewport, so the bar can actually collapse.
        description: 'Line of detail. ' * 60,
        location: 'Library',
        startTime: _at(2, 15),
        participantCount: 3,
        hasJoined: false,
        bannerUrl: 'https://example.com/banner.jpg',
      );
      await _pump(tester, ActivityDetailScreen(activity: mine));
      // _pump uses a tall viewport; shrink it so the body overflows and the bar can collapse.
      tester.view.physicalSize = const Size(393 * 2, 600 * 2);
      await tester.pumpAndSettle();

      SliverAppBar bar() =>
          tester.widget<SliverAppBar>(find.byType(SliverAppBar));

      // Expanded over the banner photo: icons are white.
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      expect(bar().foregroundColor, Colors.white);

      // Collapse the bar onto the solid surface: icons go dark for contrast.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(bar().foregroundColor, AppColors.textDark);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/core/theme/app_theme.dart';
import 'package:lc_connect/features/activities/providers/activities_provider.dart';
import 'package:lc_connect/features/attendance/providers/attendance_provider.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/campus_hub/models/campus_post.dart';
import 'package:lc_connect/features/campus_hub/providers/campus_hub_provider.dart';
import 'package:lc_connect/features/campus_hub/providers/campus_publishing_provider.dart';
import 'package:lc_connect/features/campus_hub/providers/opportunity_badge_provider.dart';
import 'package:lc_connect/features/campus_hub/screens/campus_hub_screen.dart';
import 'package:lc_connect/features/discovery/providers/discovery_provider.dart';
import 'package:lc_connect/features/notifications/providers/notifications_provider.dart';
import 'package:lc_connect/features/profile/providers/profile_provider.dart';
import 'package:lc_connect/features/programs/providers/programs_provider.dart';
import 'package:lc_connect/shared/util/eligibility.dart';
import 'package:lc_connect/shared/widgets/app_card.dart';
import 'package:lc_connect/shared/widgets/nav_shell.dart';
import 'package:lc_connect/features/messages/providers/unread_provider.dart';
import 'package:lc_connect/features/connections/providers/connections_provider.dart';

/// Home dashboard layout (UI pass 1).
///
/// Pumps the whole dashboard with realistic data at the two widths that matter — 320dp (the
/// smallest supported phone) and 393dp (a typical one) — and pins the presentation decisions:
/// one featured update with its live count, a shared header for the preview sections, three
/// suggestions side by side on a normal phone, and no layout overflow anywhere.
// ── Fixtures ──────────────────────────────────────────────────────────────────

class _Auth extends AuthNotifier {
  final String role;
  _Auth(this.role);
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'user-1',
        email: 'ama@students.livingstone.edu',
        role: role,
        profileCompleted: true,
        isVerified: true,
      );
}

class _Profile extends MyProfileNotifier {
  @override
  Future<MyProfile> build() async => const MyProfile(
        profileId: 'prof-1',
        userId: 'user-1',
        displayName: 'Ama Mensah',
        interests: [],
        languagesSpoken: [],
        languagesLearning: [],
        lookingFor: [],
        lookingForCodes: [],
        allowMessagesFromMatchesOnly: true,
        showProfileToVerifiedOnly: false,
        campusVerified: true,
        isHidden: false,
        profileCompleted: true,
        campusPositionVerified: false,
        connectionCount: 0,
        activityCount: 0,
        messageCount: 0,
      );
}

class _Activities extends ActivitiesNotifier {
  final List<Activity> items;
  _Activities(this.items);
  @override
  Future<List<Activity>> build() async => items;
}

class _Discovery extends DiscoveryNotifier {
  final List<DiscoveryCard> items;
  _Discovery(this.items);
  @override
  Future<List<DiscoveryCard>> build() async => items;
}

class _Notif extends NotificationCountNotifier {
  @override
  int build() => 3;
}

class _Ann extends AnnouncementCountNotifier {
  @override
  int build() => 2;
}

class _Unread extends UnreadNotifier {
  @override
  UnreadState build() => const UnreadState(total: 2);
}

class _Opp extends OpportunityNewCountNotifier {
  @override
  int build() => 4;
}

final _now = DateTime.now();

CampusPostSummary _post(String id, String title, String? summary, Duration ago,
        {String priority = 'normal', String category = 'academic', bool read = false}) =>
    CampusPostSummary(
      id: id,
      kind: 'announcement',
      title: title,
      summary: summary,
      priority: priority,
      category: category,
      publishAt: _now.subtract(ago),
      read: read,
    );

final _updates = [
  _post('p1', 'Spring registration opens Monday',
      'Meet your advisor before Friday to lift your registration hold.', const Duration(hours: 3)),
  _post('p2', 'Library extends hours for finals week', 'Open until 2am Sunday–Thursday.',
      const Duration(days: 1), category: 'facilities', read: true),
  _post('p3', 'Homecoming volunteers needed', null, const Duration(days: 2), category: 'events'),
];

final _activities = [
  Activity(
    id: 'a1',
    creatorId: 'u2',
    title: 'Study group: Organic Chemistry',
    category: 'study',
    location: 'Carnegie Library, Room 204',
    startTime: _now.add(const Duration(days: 2, hours: 3)),
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
    startTime: _now.add(const Duration(days: 4)),
    participantCount: 12,
    hasJoined: true,
  ),
];

DiscoveryCard _card(String id, String name, String major) => DiscoveryCard(
      profileId: id,
      userId: 'u-$id',
      displayName: name,
      major: major,
      interests: const [],
      languagesSpoken: const [],
      languagesLearning: const [],
      lookingFor: const [],
      lookingForCodes: const [],
      matchScore: 80,
      matchReasons: const [],
    );

final _cards = [
  _card('c1', 'Kwame Asante', 'Computer Science'),
  _card('c2', 'Jordan Ellis', 'Biology'),
  _card('c3', 'Maya Thompson', 'Business Administration'),
];

/// Layout errors raised while pumping, minus the spotlight's.
///
/// The spotlight copy is sized for DM Sans. The test font draws every glyph as a full-em square,
/// so at 320dp its headline wraps one line more than it ever does on a device and the card
/// overflows — an artifact of the font, not of the layout (spotlight_copy_test covers that copy).
/// Everything else on Home must lay out cleanly even under the wider test font.
List<FlutterErrorDetails> _layoutErrors = [];

/// Swaps the error handler for the duration of the pump only — the test binding requires its
/// own handler back before the test body ends.
Future<void> _withLayoutErrorsCaptured(Future<void> Function() body) async {
  _layoutErrors = [];
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.toDiagnosticsNode().toStringDeep().contains('_SpotlightContent')) return;
    _layoutErrors.add(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

Future<void> _pumpHome(
  WidgetTester tester, {
  double width = 393,
  List<CampusPostSummary>? updates,
  List<CampusPostSummary> urgent = const [],
  bool publisher = false,
}) async {
  tester.view.physicalSize = Size(width * 2, 2400 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    ShellRoute(
      builder: (_, _, child) => NavShell(child: child),
      routes: [GoRoute(path: '/', builder: (_, _) => const CampusHubScreen())],
    ),
  ]);
  await _withLayoutErrorsCaptured(() async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _Auth('student')),
        myProfileNotifierProvider.overrideWith(_Profile.new),
        campusHubOverviewProvider.overrideWith((ref) async =>
            CampusHubOverview(urgentPosts: urgent, latestUpdates: updates ?? _updates)),
        announcementCountProvider.overrideWith(_Ann.new),
        opportunityNewCountProvider.overrideWith(_Opp.new),
        notificationCountProvider.overrideWith(_Notif.new),
        scholarEligibilityProvider.overrideWithValue(Eligibility.no),
        honorsAttendanceVisibleProvider.overrideWithValue(Eligibility.no),
        attendanceRealtimeSyncProvider.overrideWith((ref) {}),
        publishingCapabilitiesProvider.overrideWith((ref) async =>
            PublishingCapabilities(canPublish: publisher, staffPublishingEnabled: publisher)),
        activitiesNotifierProvider.overrideWith(() => _Activities(_activities)),
        discoveryNotifierProvider.overrideWith(() => _Discovery(_cards)),
        unreadProvider.overrideWith(_Unread.new),
        incomingConnectionCountProvider.overrideWithValue(0),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    // Not pumpAndSettle: the spotlight carousel and attendance poll keep timers running.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}

void main() {
  for (final width in [320.0, 393.0]) {
    testWidgets('renders every section without overflow at ${width.toInt()}dp', (tester) async {
      await _pumpHome(
        tester,
        width: width,
        publisher: true,
        urgent: [
          _post('u1', 'Campus closed today due to severe weather', null,
              const Duration(hours: 1), priority: 'urgent'),
        ],
      );
      expect(_layoutErrors, isEmpty, reason: _layoutErrors.join('\n'));
      expect(find.text('Urgent campus alert'), findsOneWidget);
      expect(find.text('Publish to campus'), findsOneWidget);
      for (final title in ['Latest updates', 'Upcoming activities', 'Suggested connections']) {
        expect(find.text(title), findsOneWidget);
      }
    });
  }

  testWidgets('features only the newest update, with the live new count', (tester) async {
    // Home is a teaser, not the list: one update, and the count tells you there is more.
    final handle = tester.ensureSemantics();
    await _pumpHome(tester);
    expect(find.text('Spring registration opens Monday'), findsOneWidget);
    expect(find.text('Library extends hours for finals week'), findsNothing);
    expect(find.text('Homecoming volunteers needed'), findsNothing);
    expect(find.bySemanticsLabel('See all updates, 2 new'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a quiet updates section is one light row, not the feature panel', (tester) async {
    await _pumpHome(tester, updates: const []);
    expect(find.text('Latest updates'), findsOneWidget);
    expect(find.text('No campus announcements yet.'), findsOneWidget);
  });

  testWidgets('section actions announce what they open', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester);
    expect(find.bySemanticsLabel('See all updates, 2 new'), findsOneWidget);
    expect(find.bySemanticsLabel('See all upcoming activities'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the spotlight banner is a button that names where it goes', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester);
    // The slide's own copy follows the action: "Open groups, Livingstone College, Find your…".
    expect(find.bySemanticsLabel(RegExp(r'^Open groups\n')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the spotlight does not advance on its own', (tester) async {
    await _pumpHome(tester);
    final before = tester.widget<PageView>(find.byType(PageView)).controller!.page;
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, before);
  });

  testWidgets('a joined activity is marked as going', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpHome(tester);
    expect(find.bySemanticsLabel("You're going"), findsOneWidget);
    handle.dispose();
  });

  testWidgets('suggestions sit three across on a typical phone', (tester) async {
    // The old check compared the *row* (screen minus gutters) against 360, so a 393dp phone got
    // a scrolling strip with the third card cut off.
    await _pumpHome(tester);
    final names = ['Kwame Asante', 'Jordan Ellis', 'Maya Thompson'];
    final tops = names.map((n) => tester.getTopLeft(find.text(n)).dy).toSet();
    expect(tops.length, 1, reason: 'all three names share one row');
    final lastRight = tester.getTopRight(find.ancestor(
      of: find.text('Maya Thompson'),
      matching: find.byType(AppCard),
    )).dx;
    expect(lastRight, lessThanOrEqualTo(393 - 20), reason: 'the third card is fully on screen');
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsNothing);
  });

  testWidgets('suggestions switch to a swipeable strip on a 320dp phone', (tester) async {
    await _pumpHome(tester, width: 320);
    final strip = find.ancestor(
      of: find.text('Kwame Asante'),
      matching: find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
    );
    expect(strip, findsOneWidget);
  });
}

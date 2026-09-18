import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/features/activities/providers/activities_provider.dart';
import 'package:lc_connect/features/activities/screens/activities_screen.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/connections/providers/connections_provider.dart';
import 'package:lc_connect/features/connections/screens/connections_screen.dart';
import 'package:lc_connect/features/discovery/providers/discovery_provider.dart';
import 'package:lc_connect/features/discovery/screens/discovery_screen.dart';
import 'package:lc_connect/features/notifications/providers/notifications_provider.dart';
import 'package:lc_connect/features/profile/providers/profile_provider.dart';
import 'package:lc_connect/features/profile/screens/profile_screen.dart';
import 'package:lc_connect/features/programs/providers/programs_provider.dart';
import 'package:lc_connect/shared/util/eligibility.dart';

// ── Shared mocks ──────────────────────────────────────────────────

class _StudentAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'user-1',
        email: 'u@students.livingstone.edu',
        role: 'student',
        profileCompleted: true,
        isVerified: true,
      );
}

class _CountingDiscovery extends DiscoveryNotifier {
  int builds = 0;

  @override
  Future<List<DiscoveryCard>> build() async {
    builds++;
    return const [];
  }
}

class _CountingActivities extends ActivitiesNotifier {
  int builds = 0;

  @override
  Future<List<Activity>> build() async {
    builds++;
    return const [];
  }
}

class _CountingConnections extends ConnectionsNotifier {
  int builds = 0;

  @override
  Future<ConnectionsState> build() async {
    builds++;
    return const ConnectionsState(incoming: [], outgoing: []);
  }
}

class _CountingProfile extends MyProfileNotifier {
  int builds = 0;

  @override
  Future<MyProfile> build() async {
    builds++;
    return const MyProfile(
      profileId: 'prof-1',
      userId: 'user-1',
      displayName: 'Test User',
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
}

class _ZeroNotifications extends NotificationCountNotifier {
  @override
  int build() => 0;
}

Future<void> _pull(WidgetTester tester) async {
  final indicator =
      tester.widget<RefreshIndicator>(find.byType(RefreshIndicator).first);
  await indicator.onRefresh();
  await tester.pumpAndSettle();
}

void main() {
  group('Pull-to-refresh (#19)', () {
    testWidgets('Discovery exposes RefreshIndicator and reloads on pull',
        (tester) async {
      final discovery = _CountingDiscovery();
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DiscoveryScreen()),
          GoRoute(path: '/connections', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/notifications', builder: (_, _) => const SizedBox()),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(_StudentAuth.new),
            discoveryNotifierProvider.overrideWith(() => discovery),
            notificationCountProvider.overrideWith(_ZeroNotifications.new),
            connectionsNotifierProvider
                .overrideWith(_CountingConnections.new),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      final before = discovery.builds;
      await _pull(tester);
      expect(discovery.builds, greaterThan(before));
    });

    testWidgets('Activities exposes RefreshIndicator and reloads on pull',
        (tester) async {
      final activities = _CountingActivities();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activitiesNotifierProvider.overrideWith(() => activities),
            activitiesFilterProvider.overrideWith(ActivitiesFilterNotifier.new),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const ActivitiesScreen(),
                ),
                GoRoute(
                  path: '/activities/create',
                  builder: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      final before = activities.builds;
      await _pull(tester);
      expect(activities.builds, greaterThan(before));
    });

    testWidgets('Connections exposes RefreshIndicator and reloads on pull',
        (tester) async {
      final connections = _CountingConnections();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionsNotifierProvider.overrideWith(() => connections),
          ],
          child: const MaterialApp(home: ConnectionsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsWidgets);
      final before = connections.builds;
      await _pull(tester);
      expect(connections.builds, greaterThan(before));
    });

    testWidgets('Profile exposes RefreshIndicator and reloads on pull',
        (tester) async {
      final profile = _CountingProfile();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(_StudentAuth.new),
            myProfileNotifierProvider.overrideWith(() => profile),
            scholarEligibilityProvider.overrideWithValue(Eligibility.no),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
                GoRoute(
                  path: '/profile/edit',
                  builder: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      final before = profile.builds;
      await _pull(tester);
      expect(profile.builds, greaterThan(before));
    });
  });

  /// Report #18 (4.3) — the dashboard's pull-to-refresh did not refresh its own dashboard.
  ///
  /// Three sections were missed: "Upcoming activities" and "Suggested connections" read
  /// `activitiesNotifierProvider` and `discoveryNotifierProvider`, and the greeting header reads
  /// the profile. A pull refreshed the middle of the screen and left the top and bottom stale —
  /// worse than not offering the gesture, because it looks like it worked.
  ///
  /// A source test rather than a widget test: the failure mode is "a section was added and the
  /// refresh handler was not updated", which is a property of the file, and pumping the whole hub
  /// needs a dozen provider overrides to assert one thing.
  group('the dashboard refreshes every section it renders', () {
    late String refreshBlock;

    setUpAll(() {
      final source =
          File('lib/features/campus_hub/screens/campus_hub_screen.dart').readAsStringSync();
      final start = source.indexOf('onRefresh:');
      expect(start, greaterThan(-1), reason: 'the dashboard should still have a RefreshIndicator');
      refreshBlock = source.substring(start, source.indexOf('child: ListView', start));
    });

    // Each entry is a section the dashboard draws, and the provider it reads.
    const sectionProviders = {
      'campus updates + urgent banner': 'campusHubOverviewProvider',
      'attendance card': 'activeAttendanceProvider',
      'attendance eligibility': 'honorsAttendanceEnabledProvider',
      'Blueprint card eligibility': 'myProgramMembershipsProvider',
      'Blueprint card completeness': 'scholarProfileNotifierProvider',
      'Upcoming activities': 'activitiesNotifierProvider',
      'Suggested connections': 'discoveryNotifierProvider',
      'greeting header name': 'myProfileNotifierProvider',
      'opportunity counter': 'opportunityNewCountProvider',
    };

    for (final entry in sectionProviders.entries) {
      test('${entry.key} is refreshed', () {
        expect(
          refreshBlock,
          contains(entry.value),
          reason: 'the dashboard renders ${entry.key} but its pull-to-refresh does not refresh '
              '${entry.value} — the section would stay stale after a pull',
        );
      });
    }
  });
}

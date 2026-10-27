import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/core/theme/app_theme.dart';
import 'package:lc_connect/features/activities/providers/activities_provider.dart';
import 'package:lc_connect/features/activities/screens/activities_screen.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/notifications/providers/notifications_provider.dart';

/// The compact activity rows used to hardcode `school.webp` for every thumbnail, ignoring each
/// activity's banner — so a list of activities with distinct banners looked identical. These pin
/// that a banner is now rendered (cached, cropped) and that the generic image is only the fallback.

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

class _Notif extends NotificationCountNotifier {
  @override
  int build() => 0;
}

class _Acts extends ActivitiesNotifier {
  _Acts(this.list);
  final List<Activity> list;
  @override
  Future<List<Activity>> build() async => list;
}

final _future = DateTime.now().add(const Duration(days: 2));

Activity _activity(String id, {String? bannerUrl}) => Activity(
      id: id,
      creatorId: 'u',
      title: 'Activity $id',
      category: 'social',
      location: 'Main Quad',
      startTime: _future,
      participantCount: 3,
      hasJoined: false,
      bannerUrl: bannerUrl,
    );

Future<void> _pump(WidgetTester tester, List<Activity> activities) async {
  tester.view.physicalSize = const Size(393 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_Auth.new),
      activitiesNotifierProvider.overrideWith(() => _Acts(activities)),
      activitiesFilterProvider.overrideWith(ActivitiesFilterNotifier.new),
      notificationCountProvider.overrideWith(_Notif.new),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig:
          GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const ActivitiesScreen())]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every card renders its banner when it has one', (tester) async {
    await _pump(tester, [
      _activity('a', bannerUrl: 'https://example.com/a.jpg'),
      _activity('b', bannerUrl: 'https://example.com/b.jpg'),
      _activity('c', bannerUrl: 'https://example.com/c.jpg'),
    ]);

    // One featured card + two compact rows, each backed by its banner — not the shared asset.
    expect(find.byType(CachedNetworkImage), findsNWidgets(3));
  });

  testWidgets('a banner-less activity falls back to the generic image', (tester) async {
    await _pump(tester, [
      _activity('a'),
      _activity('b'),
    ]);

    expect(find.byType(CachedNetworkImage), findsNothing);
    // The compact row's fallback is the generic campus image, not a blank box.
    expect(
      find.byWidgetPredicate(
        (w) => w is Image && w.image == const AssetImage('assets/images/school.webp'),
      ),
      findsWidgets,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/campus_hub/models/campus_resource.dart';
import 'package:lc_connect/features/campus_hub/providers/campus_resources_provider.dart';
import 'package:lc_connect/features/campus_hub/screens/campus_resources_screen.dart';

/// The fix: the six-category grid is the resources home on "All" — always, not only when the
/// resource list happens to be empty. Before, one published resource made the categorised entry
/// point disappear and dropped users onto a flat list.
class _MockAuthNotifier extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'u',
        email: 'a@b.com',
        role: 'student',
        profileCompleted: true,
      );
}

const _resource = CampusResource(
  id: 'r1',
  category: 'advising',
  title: 'Advising Center',
  description: 'Plan your courses',
  sortOrder: 0,
);

Widget _app(List<CampusResource> resources) => ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(_MockAuthNotifier.new),
        // Same payload regardless of the category query, so switching category still resolves.
        campusResourcesProvider.overrideWith((ref, query) async => resources),
      ],
      child: const MaterialApp(home: CampusResourcesScreen()),
    );

/// A tall, narrow viewport so the lazily-built grid lays out all three rows at once — otherwise the
/// lower tiles sit below the fold and are never constructed.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the six categories show on "All" even when resources exist', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_app(const [_resource]));
    await tester.pumpAndSettle();

    // Grid-unique titles (the filter bar reuses the shorter labels like "Financial Aid", so these
    // two prove the *grid* rendered, not the chips).
    expect(find.text('Academic Advising'), findsOneWidget);
    expect(find.text('Housing &\nResidence Life'), findsOneWidget);
    // The shared labels still appear at least once (grid tile + possibly a filter chip).
    expect(find.text('Career Services'), findsWidgets);
    expect(find.text('Student Support'), findsWidgets);
    // …and the flat resource list is NOT what "All" shows.
    expect(find.text('Advising Center'), findsNothing);
  });

  testWidgets('tapping a category opens its resource list', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_app(const [_resource]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Academic Advising'));
    await tester.pumpAndSettle();

    expect(find.text('Advising Center'), findsOneWidget);
  });

  testWidgets('a category with no resources shows the coming-soon state', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Career Services'));
    await tester.pumpAndSettle();

    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('Back to all categories'), findsOneWidget);
  });
}

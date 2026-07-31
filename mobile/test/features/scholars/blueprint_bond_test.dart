import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/scholars/providers/scholars_provider.dart';
import 'package:lc_connect/features/scholars/screens/blueprint_bond_screen.dart';

class _MockScholarNotifier extends ScholarProfileNotifier {
  final ScholarProfile _fixed;
  _MockScholarNotifier(this._fixed);

  @override
  Future<ScholarProfile> build() async => _fixed;
}

class _MockAuthNotifier extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'user-me',
        email: 'me@livingstone.edu',
        role: 'student',
        profileCompleted: true,
      );
}

ScholarProfile _profile({
  String? summary,
  bool employerVisibilityConsent = false,
  bool hasHeadshot = false,
  bool hasResume = false,
  List<String> skills = const ['Python', 'Public Speaking'],
}) =>
    ScholarProfile(
      id: 'sp-1',
      userId: 'user-me',
      linkedinUrl: 'https://linkedin.com/in/scholar',
      summary: summary,
      skills: skills,
      careerInterests: const ['Consulting'],
      employerVisibilityConsent: employerVisibilityConsent,
      hasHeadshot: hasHeadshot,
      hasResume: hasResume,
    );

Widget _scope(ScholarProfile profile) {
  return ProviderScope(
    overrides: [
      scholarProfileNotifierProvider.overrideWith(() => _MockScholarNotifier(profile)),
      authNotifierProvider.overrideWith(_MockAuthNotifier.new),
    ],
    child: const MaterialApp(home: BlueprintBondScreen()),
  );
}

void main() {
  // The form is a long ListView (headshot/resume rows, three text fields, two tag inputs, a
  // consent switch) — give the test viewport enough height that everything is laid out without
  // needing to scroll, rather than fighting the sliver cache extent in every test.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('BlueprintBondScreen shows the professional-profile form', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_scope(_profile()));
    await tester.pumpAndSettle();

    expect(find.text('Blueprint Bond'), findsOneWidget);
    expect(find.text('LinkedIn URL'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Python'), findsOneWidget);
    expect(find.text('Public Speaking'), findsOneWidget);
  });

  testWidgets('shows Upload prompts when no headshot/resume on file', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_scope(_profile()));
    await tester.pumpAndSettle();

    expect(find.text('Upload'), findsNWidgets(2));
    expect(find.text('Replace'), findsNothing);
  });

  testWidgets('shows Replace + View once headshot/resume are on file', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_scope(_profile(hasHeadshot: true, hasResume: true)));
    await tester.pumpAndSettle();

    expect(find.text('Replace'), findsNWidgets(2));
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('employer visibility switch reflects consent state', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_scope(_profile(employerVisibilityConsent: true)));
    await tester.pumpAndSettle();

    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isTrue);
  });
}

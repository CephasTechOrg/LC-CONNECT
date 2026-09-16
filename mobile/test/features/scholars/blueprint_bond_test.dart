import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/scholars/providers/scholars_provider.dart';
import 'package:lc_connect/features/scholars/screens/blueprint_bond_screen.dart';
import 'package:lc_connect/features/scholars/widgets/blueprint_bond_card.dart';
import 'package:lc_connect/features/programs/providers/programs_provider.dart';
import 'package:lc_connect/shared/util/eligibility.dart';

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

/// `isComplete` and `missingFields` are supplied, not derived — the client no longer computes
/// completeness (the rule includes a minimum summary length and employer consent, and lives in
/// `scholars/service.py::missing_profile_fields`).
ScholarProfile _profile({
  String? summary,
  bool employerVisibilityConsent = false,
  bool hasHeadshot = false,
  bool hasResume = false,
  List<String> skills = const ['Python', 'Public Speaking'],
  bool isComplete = false,
  List<String> missingFields = const ['summary'],
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
      isComplete: isComplete,
      missingFields: isComplete ? const [] : missingFields,
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
  _cardTests();
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

// ── BlueprintBondCard: where it shows and where it disappears ────────────────────
//
// The prompt on Campus Hub is a call-to-action, so it must give way once there's nothing left to
// do — otherwise it becomes permanent clutter on a feed students scroll daily.
//
// Per beta report #6 it now **disappears entirely** when complete. An earlier design left a quiet
// status row behind, because vanishing removed the only place a verified scholar could see they
// were one; the permanent Profile entry row is what makes vanishing safe, so it is load-bearing
// rather than decorative and is asserted below.

Widget _card(BlueprintBondStyle style, {required bool scholar, ScholarProfile? profile}) {
  return ProviderScope(
    overrides: [
      scholarEligibilityProvider.overrideWithValue(scholar ? Eligibility.yes : Eligibility.no),
      if (profile != null)
        scholarProfileNotifierProvider.overrideWith(() => _MockScholarNotifier(profile)),
    ],
    child: MaterialApp(home: Scaffold(body: BlueprintBondCard(style: style))),
  );
}

void _cardTests() {
  group('BlueprintBondCard', () {
    testWidgets('renders nothing at all for a non-scholar', (tester) async {
      await tester.pumpWidget(_card(BlueprintBondStyle.entry, scholar: false));
      await tester.pumpAndSettle();
      expect(find.text('Blueprint Bond'), findsNothing);
    });

    testWidgets('Campus Hub prompt SHOWS while the profile is incomplete', (tester) async {
      await tester.pumpWidget(_card(BlueprintBondStyle.prompt,
          scholar: true, profile: _profile(summary: null)));
      await tester.pumpAndSettle();
      expect(find.text('Finish your Blueprint Bond profile'), findsOneWidget);
    });

    testWidgets('Campus Hub prompt LEAVES the dashboard entirely once complete', (tester) async {
      await tester.pumpWidget(_card(BlueprintBondStyle.prompt,
          scholar: true, profile: _profile(isComplete: true)));
      await tester.pumpAndSettle();
      expect(find.text('Finish your Blueprint Bond profile'), findsNothing);
      // No residue of any kind — this is the behaviour report #6 asked for.
      expect(find.text('Honors Student'), findsNothing);
      expect(find.text('Blueprint Bond'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('the prompt names what is still outstanding', (tester) async {
      await tester.pumpWidget(_card(
        BlueprintBondStyle.prompt,
        scholar: true,
        profile: _profile(missingFields: const ['resume']),
      ));
      await tester.pumpAndSettle();
      // A generic nudge makes the student open the screen to find out what is left.
      expect(find.textContaining('Still needed'), findsOneWidget);
      expect(find.textContaining('résumé'), findsOneWidget);
    });

    testWidgets('the prompt summarises when several fields are outstanding', (tester) async {
      await tester.pumpWidget(_card(
        BlueprintBondStyle.prompt,
        scholar: true,
        profile: _profile(
          missingFields: const ['summary', 'headshot', 'resume', 'skills'],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('and 2 more'), findsOneWidget);
    });

    testWidgets('the client does not second-guess the server on completeness', (tester) async {
      // Deliberately contradictory: nothing filled in locally, but the server says complete.
      // The server owns the rule (it also checks summary length and consent), so it wins.
      await tester.pumpWidget(_card(BlueprintBondStyle.prompt,
          scholar: true, profile: _profile(summary: null, isComplete: true)));
      await tester.pumpAndSettle();
      expect(find.text('Finish your Blueprint Bond profile'), findsNothing);
    });

    testWidgets('Campus Hub prompt stays across remount while still incomplete', (tester) async {
      // Regression for the blink: remounting Hub must not shrink→grow the prompt when the
      // scholar + incomplete profile are already known (membership providers are keepAlive).
      await tester.pumpWidget(_card(BlueprintBondStyle.prompt,
          scholar: true, profile: _profile(summary: null)));
      await tester.pumpAndSettle();
      expect(find.text('Finish your Blueprint Bond profile'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_card(BlueprintBondStyle.prompt,
          scholar: true, profile: _profile(summary: null)));
      // First frame after remount — must already show the prompt (no empty flash).
      await tester.pump();
      expect(find.text('Finish your Blueprint Bond profile'), findsOneWidget);
    });

    testWidgets('Profile entry STAYS once complete, showing completed status', (tester) async {
      // Load-bearing: this is the only place a finished scholar can still see their status now
      // that the dashboard prompt retires.
      await tester.pumpWidget(_card(BlueprintBondStyle.entry,
          scholar: true, profile: _profile(isComplete: true)));
      await tester.pumpAndSettle();
      expect(find.text('Honors Student'), findsOneWidget);
      expect(find.text('Blueprint Bond · profile complete'), findsOneWidget);
    });

    testWidgets('Profile entry asserts neither state when the profile cannot be read',
        (tester) async {
      // No profile override → the notifier errors out in the test harness. Previously this
      // rendered "profile incomplete" with an amber dot, which may simply be untrue.
      await tester.pumpWidget(_card(BlueprintBondStyle.entry, scholar: true));
      await tester.pumpAndSettle();
      expect(find.text('Blueprint Bond · profile complete'), findsNothing);
      expect(find.text('Blueprint Bond · profile incomplete'), findsNothing);
      expect(find.text('Blueprint Bond'), findsOneWidget);
    });

    testWidgets('Profile entry shows incomplete status when unfinished', (tester) async {
      await tester.pumpWidget(_card(BlueprintBondStyle.entry,
          scholar: true, profile: _profile(summary: null)));
      await tester.pumpAndSettle();
      expect(find.text('Honors Student'), findsOneWidget);
      expect(find.text('Blueprint Bond · profile incomplete'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/attendance/providers/attendance_provider.dart';
import 'package:lc_connect/features/attendance/providers/attendance_scanner_provider.dart';
import 'package:lc_connect/features/attendance/widgets/attendance_open_card.dart';
import 'package:lc_connect/features/notifications/data/notification_models.dart';
import 'package:lc_connect/features/programs/providers/programs_provider.dart';
import 'package:lc_connect/shared/util/eligibility.dart';
void main() {
  /// Regression: the scanner flashed "This attendance session is not available for your account"
  /// before opening the camera.
  ///
  /// The cause was reading a *sync* provider on the first frame. Both
  /// `scholarEligibilityProvider` and `honorsAttendanceVisibleProvider` report
  /// [Eligibility.pending] while their requests are still in flight, which is right for painting a
  /// widget and wrong for making a decision — a genuine scholar was told they were not one. The
  /// awaitable variants exist so callers that decide can wait for the real answer.
  ///
  /// `pending` is now a distinct state from `no`, so "still loading" can no longer be mistaken for
  /// a denial by any caller, not just the ones that remembered to await.
  group('loading is not a denial', () {
    ProgramMembership scholar() => const ProgramMembership(
          id: 'm1',
          userId: 'u1',
          status: 'active',
          programSlug: presidentialScholarsSlug,
          programName: 'Presidential Scholars',
        );

    ProviderContainer containerWithSlowMemberships() => ProviderContainer(
          overrides: [
            myProgramMembershipsProvider.overrideWith((ref) async {
              await Future<void>.delayed(const Duration(milliseconds: 40));
              return [scholar()];
            }),
            honorsAttendanceEnabledProvider.overrideWith((ref) async => true),
          ],
        );

    test('the sync provider reports pending — not a denial — while memberships load', () {
      final c = containerWithSlowMemberships();
      addTearDown(c.dispose);
      // This is the value the scanner used to act on, one frame after mount. It used to be
      // `false`, indistinguishable from a real "not a scholar"; it is now explicitly `pending`.
      final eligibility = c.read(scholarEligibilityProvider);
      expect(eligibility, Eligibility.pending);
      expect(eligibility.isPermitted, isFalse, reason: 'still must not render the surface yet');
      expect(eligibility.needsRetry, isFalse, reason: 'loading is not a failure to report');
      expect(eligibility, isNot(Eligibility.no));
    });

    // Each of these reads through a listener rather than `.future`: subscribing keeps the provider
    // alive and lets its body settle into `AsyncError`, whereas awaiting `.future` on a throwing
    // override leaves the error future unobserved and hangs the test.
    test('a failed membership request is unknown, never a denial', () async {
      final c = ProviderContainer(overrides: [
        myProgramMembershipsProvider.overrideWith((ref) async => throw Exception('offline')),
        honorsAttendanceEnabledProvider.overrideWith((ref) async => true),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(scholarEligibilityProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final eligibility = sub.read();
      expect(eligibility, Eligibility.unknown);
      expect(eligibility, isNot(Eligibility.no), reason: 'the original silent-hide bug');
      expect(eligibility.needsRetry, isTrue);
    });

    test('a failed feature-flag request is unknown, not "feature off"', () async {
      final c = ProviderContainer(overrides: [
        myProgramMembershipsProvider.overrideWith((ref) async => [scholar()]),
        honorsAttendanceEnabledProvider.overrideWith((ref) async => throw Exception('timeout')),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(honorsAttendanceVisibleProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      // Previously `catch (_) { return false; }` made this indistinguishable from the flag
      // genuinely being off, hiding every attendance surface for the rest of the session.
      expect(sub.read(), Eligibility.unknown);
    });

    test('a confirmed non-scholar outranks an unreadable feature flag', () async {
      final c = ProviderContainer(overrides: [
        myProgramMembershipsProvider.overrideWith((ref) async => <ProgramMembership>[]),
        honorsAttendanceEnabledProvider.overrideWith((ref) async => throw Exception('timeout')),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(honorsAttendanceVisibleProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      // A settled "no" needs no retry — offering one would be a dead end.
      expect(sub.read(), Eligibility.no);
      expect(sub.read().needsRetry, isFalse);
    });
  });

  group('QrAttendancePayload', () {
    test('parses a valid QR JSON payload', () {
      const raw = '{"v":1,"session_id":"sess-1","challenge_id":"chal-1","expires_at":"2026-08-31T12:00:00Z","token":"abc123"}';
      final payload = QrAttendancePayload.tryParse(raw);
      expect(payload, isNotNull);
      expect(payload!.sessionId, 'sess-1');
      expect(payload.challengeId, 'chal-1');
      expect(payload.token, 'abc123');
    });

    test('returns null for invalid payloads', () {
      expect(QrAttendancePayload.tryParse('not-json'), isNull);
      expect(QrAttendancePayload.tryParse('{"v":1}'), isNull);
    });
  });

  group('AttendanceOpenCard', () {
    AttendanceSessionInfo session() => AttendanceSessionInfo(
          id: 'sess-1',
          title: 'Honors Class',
          openedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          presentUntil: DateTime.now().add(const Duration(minutes: 3)),
          lateUntil: DateTime.now().add(const Duration(minutes: 5)),
          status: 'open',
        );

    Widget cardWith(ActiveAttendanceState state) => ProviderScope(
          overrides: [
            honorsAttendanceVisibleProvider.overrideWithValue(Eligibility.yes),
            activeAttendanceProvider.overrideWith((ref) async => state),
          ],
          child: const MaterialApp(home: Scaffold(body: AttendanceOpenCard())),
        );

    testWidgets('renders nothing for non-scholars', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            honorsAttendanceVisibleProvider.overrideWithValue(Eligibility.no),
          ],
          child: const MaterialApp(home: Scaffold(body: AttendanceOpenCard())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Attendance is open'), findsNothing);
    });

    testWidgets('shows the card when a session is active', (tester) async {
      final session = AttendanceSessionInfo(
        id: 'sess-1',
        title: 'Honors Class',
        openedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        presentUntil: DateTime.now().add(const Duration(minutes: 3)),
        lateUntil: DateTime.now().add(const Duration(minutes: 5)),
        status: 'open',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            honorsAttendanceVisibleProvider.overrideWithValue(Eligibility.yes),
            activeAttendanceProvider.overrideWith(
              (ref) async => ActiveAttendanceState(open: true, session: session),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: AttendanceOpenCard())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Attendance is open'), findsOneWidget);
      expect(find.text('Honors Class'), findsOneWidget);
      expect(find.text('Scan to Check In'), findsOneWidget);
    });

    /// The card used to keep prompting "Scan to Check In" right through a successful check-in,
    /// until the session closed — an action that could no longer do anything.
    testWidgets('stops prompting once the student has checked in', (tester) async {
      await tester.pumpWidget(cardWith(
        ActiveAttendanceState(open: true, session: session(), studentStatus: 'present'),
      ));
      await tester.pumpAndSettle();

      expect(find.text("You're checked in"), findsOneWidget);
      expect(find.text('Scan to Check In'), findsNothing);
      expect(find.text('Attendance is open'), findsNothing);
      // The countdown is still meaningful — the session has not closed.
      expect(find.textContaining('Closes in'), findsOneWidget);
    });

    testWidgets('a late check-in is not reported as an on-time one', (tester) async {
      await tester.pumpWidget(cardWith(
        ActiveAttendanceState(open: true, session: session(), studentStatus: 'late'),
      ));
      await tester.pumpAndSettle();
      expect(find.text("You're checked in — marked late"), findsOneWidget);
    });

    testWidgets('the checked-in card is no longer tappable', (tester) async {
      await tester.pumpWidget(cardWith(
        ActiveAttendanceState(open: true, session: session(), studentStatus: 'present'),
      ));
      await tester.pumpAndSettle();
      // A dead affordance is worse than none: nothing the tap could achieve remains.
      expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    });

    testWidgets('an un-checked-in card is tappable', (tester) async {
      await tester.pumpWidget(
        cardWith(ActiveAttendanceState(open: true, session: session())),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNotNull);
    });

    testWidgets('hides itself when the session is closed', (tester) async {
      await tester.pumpWidget(cardWith(ActiveAttendanceState.closed()));
      await tester.pumpAndSettle();
      expect(find.text('Attendance is open'), findsNothing);
      expect(find.text("You're checked in"), findsNothing);
    });

    testWidgets('an eligibility failure hides the card rather than asserting it is open',
        (tester) async {
      // `unknown`, not `no` — recovery is via pull-to-refresh/resume/reconnect, and the card must
      // not claim a session state it could not read.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            honorsAttendanceVisibleProvider.overrideWithValue(Eligibility.unknown),
          ],
          child: const MaterialApp(home: Scaffold(body: AttendanceOpenCard())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Attendance is open'), findsNothing);
    });
  });

  test('honors_attendance_open notification routes to scanner', () {
    final notification = AppNotification(
      id: 'n1',
      type: 'honors_attendance_open',
      read: false,
      createdAt: DateTime(2026, 8, 31),
    );
    expect(notification.route, '/attendance/scan');
    expect(notification.message, contains('Honors attendance is open'));
  });
}

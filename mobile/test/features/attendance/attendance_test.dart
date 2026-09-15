import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/attendance/providers/attendance_provider.dart';
import 'package:lc_connect/features/attendance/providers/attendance_scanner_provider.dart';
import 'package:lc_connect/features/attendance/widgets/attendance_open_card.dart';
import 'package:lc_connect/features/notifications/data/notification_models.dart';
import 'package:lc_connect/features/programs/providers/programs_provider.dart';
void main() {
  /// Regression: the scanner flashed "This attendance session is not available for your account"
  /// before opening the camera.
  ///
  /// The cause was reading a *sync* provider on the first frame. Both
  /// `isVerifiedScholarProvider` and `honorsAttendanceVisibleProvider` answer `false` while
  /// their requests are still in flight, which is right for painting a widget and wrong for
  /// making a decision — a genuine scholar was told they were not one. The awaitable variants
  /// exist so callers that decide can wait for the real answer.
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

    test('the sync provider says false while memberships load — by design', () {
      final c = containerWithSlowMemberships();
      addTearDown(c.dispose);
      // This is the value the scanner used to act on, one frame after mount.
      expect(c.read(isVerifiedScholarProvider), isFalse);
    });

    test('the awaitable provider waits and answers true', () async {
      final c = containerWithSlowMemberships();
      addTearDown(c.dispose);
      expect(await c.read(isVerifiedScholarFutureProvider.future), isTrue);
    });

    test('attendance visibility resolves true for a scholar once loaded', () async {
      final c = containerWithSlowMemberships();
      addTearDown(c.dispose);
      expect(await c.read(honorsAttendanceVisibleFutureProvider.future), isTrue);
    });

    test('still false for a genuine non-scholar', () async {
      final c = ProviderContainer(overrides: [
        myProgramMembershipsProvider.overrideWith((ref) async => <ProgramMembership>[]),
        honorsAttendanceEnabledProvider.overrideWith((ref) async => true),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(honorsAttendanceVisibleFutureProvider.future), isFalse);
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
    testWidgets('renders nothing for non-scholars', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            honorsAttendanceVisibleProvider.overrideWithValue(false),
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
            honorsAttendanceVisibleProvider.overrideWithValue(true),
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/attendance/providers/attendance_provider.dart';
import 'package:lc_connect/features/attendance/widgets/attendance_result.dart';

final _session = AttendanceSessionInfo(
  id: 's1',
  title: 'HON 201',
  openedAt: DateTime(2026, 10, 25, 9),
  presentUntil: DateTime(2026, 10, 25, 9, 15),
  status: 'open',
);

AttendanceCheckInResult _result(String status, {bool already = false}) => AttendanceCheckInResult(
      status: status,
      checkedInAt: DateTime(2026, 10, 25, 9, 6),
      sessionId: 's1',
      message: 'ok',
      alreadyCheckedIn: already,
    );

Future<void> _pump(WidgetTester tester, Widget view) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: view)));

void main() {
  testWidgets('a fresh check-in reads as present, with a receipt', (tester) async {
    await _pump(tester, AttendanceResultView(session: _session, result: _result('present'), onDone: () {}));
    expect(find.text("You're checked in"), findsOneWidget);
    expect(find.text('HON 201'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
  });

  testWidgets('late is said plainly, not dressed as present', (tester) async {
    await _pump(tester, AttendanceResultView(session: _session, result: _result('late'), onDone: () {}));
    expect(find.text('Checked in late'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Present'), findsNothing);
  });

  testWidgets('a repeat scan says it was already done', (tester) async {
    await _pump(
      tester,
      AttendanceResultView(session: _session, result: _result('present', already: true), onDone: () {}),
    );
    expect(find.text("You're already checked in"), findsOneWidget);
  });

  testWidgets('a connection problem offers to try again, not to scan again', (tester) async {
    // It used to say "Scan again" while the button actually re-ran the access check.
    await _pump(
      tester,
      AttendanceResultView(
        errorMessage: "We couldn't check your attendance access.",
        issue: AttendanceIssue.connection,
        onScanAgain: () {},
      ),
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Scan again'), findsNothing);
  });

  testWidgets('a rejected code offers another scan', (tester) async {
    await _pump(
      tester,
      AttendanceResultView(errorMessage: 'Code expired', issue: AttendanceIssue.badCode, onScanAgain: () {}),
    );
    expect(find.text('Code not recognised'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
  });

  testWidgets('a closed session says so once and only offers Done', (tester) async {
    await _pump(
      tester,
      AttendanceResultView(errorMessage: 'Attendance is closed.', issue: AttendanceIssue.closed, onDone: () {}),
    );
    expect(find.text('Attendance is closed'), findsOneWidget);
    expect(find.text('Attendance is closed.'), findsNothing, reason: 'the server line repeats the title');
    expect(find.text('Done'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/safety/providers/safety_provider.dart';
import 'package:lc_connect/features/safety/widgets/safety_sheet.dart';

// ── Mock service ──────────────────────────────────────────────────
class _MockSafetyService extends SafetyService {
  bool blockCalled = false;
  String? lastBlockedId;
  bool reportCalled = false;
  String? lastReportReason;

  @override
  Future<void> blockUser(String userId) async {
    blockCalled = true;
    lastBlockedId = userId;
  }

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? details,
  }) async {
    reportCalled = true;
    lastReportReason = reason;
  }
}

// ── Helper: page with a button that opens the safety sheet ────────
Widget _page(
  _MockSafetyService mock, {
  String name = 'Alex',
  String userId = 'user-123',
  VoidCallback? onBlocked,
}) {
  return MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open'),
            onPressed: () => showSafetySheet(
              context: ctx,
              targetUserId: userId,
              targetName: name,
              safetyService: mock,
              onBlocked: onBlocked ?? () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Safety sheet — options', () {
    testWidgets('opens when triggered', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.text('Report Alex'), findsOneWidget);
      expect(find.text('Block Alex'), findsOneWidget);
    });

    testWidgets('shows report description', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.text('Flag inappropriate behavior anonymously'),
          findsOneWidget);
    });

    testWidgets('shows block description', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(
        find.text("They won't see your profile or be able to message you"),
        findsOneWidget,
      );
    });

    testWidgets('uses target name in labels', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService(), name: 'Jordan'));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.text('Report Jordan'), findsOneWidget);
      expect(find.text('Block Jordan'), findsOneWidget);
    });
  });

  group('Safety sheet — report flow', () {
    testWidgets('tapping Report opens reason picker', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Alex'));
      await tester.pumpAndSettle();
      expect(find.text('Why are you reporting Alex?'), findsOneWidget);
    });

    testWidgets('reason picker shows all reasons', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Alex'));
      await tester.pumpAndSettle();
      expect(find.text('Harassment or bullying'), findsOneWidget);
      expect(find.text('Spam or fake profile'), findsOneWidget);
      expect(find.text('Inappropriate content'), findsOneWidget);
      expect(find.text('Hate speech or discrimination'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('submit button is disabled before selecting reason',
        (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Alex'));
      await tester.pumpAndSettle();
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('submit button enables after selecting reason', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other'));
      await tester.pump();
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('submitting calls reportUser with selected reason',
        (tester) async {
      final mock = _MockSafetyService();
      await tester.pumpWidget(_page(mock));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam or fake profile'));
      await tester.pump();
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();
      expect(mock.reportCalled, isTrue);
      expect(mock.lastReportReason, 'Spam or fake profile');
    });

    testWidgets('success snackbar appears after report', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other'));
      await tester.pump();
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();
      expect(
        find.text(
            'Report submitted. Thank you for keeping LC Connect safe.'),
        findsOneWidget,
      );
    });
  });

  group('Safety sheet — block flow', () {
    testWidgets('tapping Block shows confirmation dialog', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block Alex'));
      await tester.pumpAndSettle();
      expect(find.text('Block Alex?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Block'), findsWidgets);
    });

    testWidgets('cancel closes dialog without blocking', (tester) async {
      final mock = _MockSafetyService();
      await tester.pumpWidget(_page(mock));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(mock.blockCalled, isFalse);
    });

    testWidgets('confirming block calls blockUser', (tester) async {
      final mock = _MockSafetyService();
      await tester.pumpWidget(_page(mock, userId: 'uid-42'));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block Alex'));
      await tester.pumpAndSettle();
      // Tap the "Block" action in the dialog (not the ListTile one)
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      expect(mock.blockCalled, isTrue);
      expect(mock.lastBlockedId, 'uid-42');
    });

    testWidgets('confirming block fires onBlocked callback', (tester) async {
      bool called = false;
      await tester.pumpWidget(
          _page(_MockSafetyService(), onBlocked: () => called = true));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });

    testWidgets('success snackbar appears after block', (tester) async {
      await tester.pumpWidget(_page(_MockSafetyService()));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      expect(find.text('Alex has been blocked.'), findsOneWidget);
    });
  });
}

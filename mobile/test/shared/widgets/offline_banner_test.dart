import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/health_provider.dart';
import 'package:lc_connect/shared/widgets/offline_banner.dart';

class _FixedStatus extends BackendStatusNotifier {
  _FixedStatus(this.fixed);
  final BackendStatus fixed;

  @override
  BackendStatus build() => fixed;
}

class _RecordingStatus extends BackendStatusNotifier {
  int checkCount = 0;

  @override
  BackendStatus build() => BackendStatus.offline;

  @override
  Future<void> checkNow() async {
    checkCount++;
  }
}

Widget _harness({
  required BackendStatusNotifier Function() create,
  double topPadding = 0,
}) {
  return ProviderScope(
    overrides: [
      backendStatusProvider.overrideWith(create),
    ],
    child: MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(top: topPadding)),
      child: const MaterialApp(
        home: AppConnectivityChrome(
          child: Scaffold(body: Text('content')),
        ),
      ),
    ),
  );
}

void main() {
  group('OfflineBannerHost (#18)', () {
    testWidgets('shows clean strip when backend is offline', (tester) async {
      await tester.pumpWidget(_harness(create: () => _FixedStatus(BackendStatus.offline)));
      await tester.pumpAndSettle();

      expect(find.text("You're offline"), findsOneWidget);
      expect(find.text('Changes will sync when you\'re back online'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('hides strip when backend is online', (tester) async {
      await tester.pumpWidget(_harness(create: () => _FixedStatus(BackendStatus.online)));
      await tester.pumpAndSettle();

      expect(find.text("You're offline"), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('stays hidden while still checking', (tester) async {
      await tester.pumpWidget(_harness(create: () => _FixedStatus(BackendStatus.checking)));
      await tester.pumpAndSettle();

      expect(find.text("You're offline"), findsNothing);
    });

    testWidgets('Retry triggers an immediate reachability check', (tester) async {
      final recording = _RecordingStatus();
      await tester.pumpWidget(_harness(create: () => recording));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(recording.checkCount, 1);
    });

    testWidgets('offline chrome zeros body top inset to avoid double SafeArea', (tester) async {
      await tester.pumpWidget(
        _harness(create: () => _FixedStatus(BackendStatus.offline), topPadding: 47),
      );
      await tester.pumpAndSettle();

      final bodyContext = tester.element(find.text('content'));
      expect(MediaQuery.paddingOf(bodyContext).top, 0);
    });
  });

  group('BackendStatusNotifier', () {
    test('reportUnreachable flips state to offline', () {
      final container = ProviderContainer(
        overrides: [
          backendStatusProvider.overrideWith(() => _FixedStatus(BackendStatus.online)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(backendStatusProvider), BackendStatus.online);
      container.read(backendStatusProvider.notifier).reportUnreachable();
      expect(container.read(backendStatusProvider), BackendStatus.offline);
    });
  });
}

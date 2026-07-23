import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';

void main() {
  group('RealtimeLifecycleObserver', () {
    test('paused + detached → background; resumed → foreground', () {
      var bg = 0;
      var fg = 0;
      final obs = RealtimeLifecycleObserver(
        onBackground: () => bg++,
        onForeground: () => fg++,
      );

      obs.didChangeAppLifecycleState(AppLifecycleState.paused);
      obs.didChangeAppLifecycleState(AppLifecycleState.detached);
      obs.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(bg, 2);
      expect(fg, 1);
    });

    test('transient states (inactive/hidden) are ignored', () {
      var calls = 0;
      final obs = RealtimeLifecycleObserver(
        onBackground: () => calls++,
        onForeground: () => calls++,
      );

      obs.didChangeAppLifecycleState(AppLifecycleState.inactive);
      obs.didChangeAppLifecycleState(AppLifecycleState.hidden);

      expect(calls, 0); // control-centre / app-switcher must not drop the socket
    });
  });

  group('RealtimeClient.suspend', () {
    test('closes to disconnected without scheduling a reconnect', () {
      final client = RealtimeClient(
        url: Uri.parse('ws://localhost:0/ws'),
        tokenProvider: () async => null,
      );
      addTearDown(client.dispose);

      client.subscribe('conv-1'); // registered even before ready
      client.suspend();

      // Disconnected and stable — no pending reconnect timer would fail this test's teardown.
      expect(client.status.value, RealtimeStatus.disconnected);
    });
  });
}

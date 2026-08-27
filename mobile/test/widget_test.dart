import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/health_provider.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/main.dart';

/// Signed-out auth that never touches Supabase, so the app boots straight to the
/// login route without a live backend.
class _SignedOutAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => null;
}

/// No network probes — the real notifier would leave pending Dio timers.
class _OnlineStatus extends BackendStatusNotifier {
  @override
  BackendStatus build() => BackendStatus.online;
}

void main() {
  setUpAll(() {
    // AppConstants.apiBaseUrl (read while building the API client) requires dotenv.
    dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test',
    );
  });

  testWidgets('App launches without crash', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(_SignedOutAuth.new),
          backendStatusProvider.overrideWith(_OnlineStatus.new),
        ],
        child: const LcConnectApp(),
      ),
    );
    await tester.pump();
    // App shell rendered (login route) without throwing.
    expect(find.byType(LcConnectApp), findsOneWidget);
  });
}

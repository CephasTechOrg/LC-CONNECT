import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/api/health_provider.dart';
import 'core/config/startup_config.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/router/pending_deep_link.dart';
import 'core/storage/secure_session_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/messages/data/chat_draft_store.dart';
import 'features/messages/providers/delivery_ack_provider.dart';
import 'features/messages/providers/in_app_message_listener.dart';
import 'shared/widgets/dismiss_keyboard.dart';
import 'shared/widgets/offline_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Config problems end at a screen that names them, never a black screen — see [StartupConfig].
  final problems = <String>[];
  final config = await StartupConfig.load(problems: problems);
  if (config == null) {
    runApp(StartupConfigErrorApp(problems: problems));
    return;
  }

  final supabaseUrl = config.supabaseUrl;
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: config.supabaseAnonKey,
    // Without this the session (refresh token included) persists to SharedPreferences in
    // plaintext — see `SecureSessionLocalStorage` for why that matters and what it costs.
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionLocalStorage(
        // Same key Supabase derives internally, so there is never a second session record.
        persistSessionKey: 'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
      ),
      pkceAsyncStorage: const SecurePkceStorage(),
    ),
  );
  await NotificationService.instance.initialize(); // guarded — no-op until Firebase is set up
  runApp(const ProviderScope(child: LcConnectApp()));
}

class LcConnectApp extends ConsumerWidget {
  const LcConnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationRegistrarProvider); // registers the FCM token in step with auth
    ref.watch(deepLinkDrainProvider); // performs queued notification taps once the app can navigate
    ref.watch(inAppMessageListenerProvider); // pops in-app banners for foreground messages
    ref.watch(deliveryAckProvider); // acknowledges receipt so senders get a delivered tick
    ref.watch(draftPruneProvider); // drops composer drafts untouched for 30 days
    ref.watch(backendStatusProvider); // keep reachability probes alive app-wide
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'LC Connect',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // `DismissKeyboardOnTap` was written for the chat screen and used in 2 of the 24 screens
      // that have a text field. Hoisting it here covers all of them: it uses
      // `HitTestBehavior.translucent`, so it takes part in hit testing without consuming the
      // gesture — buttons, links and list taps inside still win, and only taps nothing else
      // claims reach it.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.4,
        child: DismissKeyboardOnTap(
          child: AppConnectivityChrome(child: child),
        ),
      ),
    );
  }
}

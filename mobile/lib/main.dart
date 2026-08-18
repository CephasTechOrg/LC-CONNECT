import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/notifications/in_app_banner.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/secure_session_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/messages/providers/in_app_message_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final supabaseUrl = dotenv.env['SUPABASE_URL']!;
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
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
    ref.watch(inAppMessageListenerProvider); // pops in-app banners for foreground messages
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'LC Connect',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Float the in-app banner above every route.
      builder: (context, child) => Stack(
        children: [
          ?child,
          const InAppBannerHost(),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// The environment values the app cannot start without.
///
/// `main()` used to read these with bare null-assertions
/// (`dotenv.env['SUPABASE_URL']!`) before `runApp`, so a build made from a checkout without
/// `.env` — or with a key renamed — died inside `main()` with an unhandled cast error and showed
/// a black screen. Nothing reached the log a tester could read back to us, and
/// `dotenv.load` itself throws when the asset is not bundled, before any key is even looked at.
///
/// Both failures now end at a screen that names what is missing. Compare
/// `AppConstants.apiBaseUrl`, which has always degraded gracefully.
class StartupConfig {
  final String supabaseUrl;
  final String supabaseAnonKey;

  const StartupConfig({required this.supabaseUrl, required this.supabaseAnonKey});

  /// Loads `.env`, then validates it. Returns null when something is missing, and fills
  /// [problems] with lines fit to show a non-developer holding a test build.
  static Future<StartupConfig?> load({required List<String> problems}) async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Thrown when `.env` is not bundled as an asset at all (see pubspec `assets:`), which is
      // the whole-file version of a missing key rather than a different kind of problem.
      problems.add('The .env file is missing from this build.');
      return null;
    }
    return validate(dotenv.env, problems: problems);
  }

  /// The validation half, kept free of dotenv so it can be exercised directly.
  ///
  /// Treats blank and whitespace-only as missing: a key left as `SUPABASE_URL=` in a copied
  /// `.env` is not configured, and passing an empty string to `Supabase.initialize` fails later
  /// and further away, with a worse message.
  static StartupConfig? validate(
    Map<String, String> env, {
    required List<String> problems,
  }) {
    String? read(String key) {
      final value = env[key];
      return (value == null || value.trim().isEmpty) ? null : value.trim();
    }

    final url = read('SUPABASE_URL');
    final anonKey = read('SUPABASE_ANON_KEY');
    if (url == null) problems.add('SUPABASE_URL is not set.');
    if (anonKey == null) problems.add('SUPABASE_ANON_KEY is not set.');
    if (url == null || anonKey == null) return null;

    return StartupConfig(supabaseUrl: url, supabaseAnonKey: anonKey);
  }
}

/// Shown instead of the app when [StartupConfig.load] fails.
///
/// Deliberately plain: it runs before Supabase, the router, the theme extensions and any
/// provider scope exist, so it must not depend on any of them.
class StartupConfigErrorApp extends StatelessWidget {
  final List<String> problems;
  const StartupConfigErrorApp({super.key, required this.problems});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LC Connect',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.build_circle_outlined,
                      size: 44, color: AppColors.textMuted),
                  const SizedBox(height: 18),
                  Text(
                    'This build is not configured',
                    style: GoogleFonts.dmSans(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'LC Connect cannot start. Send this screen to whoever gave you the build:',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final problem in problems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• $problem',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                          height: 1.45,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

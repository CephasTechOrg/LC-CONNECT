import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/config/startup_config.dart';

/// `main()` used to read these keys with bare `!`, so a build without `.env` — or with a key
/// renamed — died inside `main()` before any UI existed. A tester saw a black screen and could
/// tell us nothing about why.
void main() {
  group('StartupConfig.validate', () {
    test('accepts a complete env and trims it', () {
      final problems = <String>[];
      final config = StartupConfig.validate(
        {'SUPABASE_URL': '  https://x.supabase.co  ', 'SUPABASE_ANON_KEY': ' key '},
        problems: problems,
      );
      expect(problems, isEmpty);
      expect(config, isNotNull);
      expect(config!.supabaseUrl, 'https://x.supabase.co');
      expect(config.supabaseAnonKey, 'key');
    });

    test('names every missing key, not just the first', () {
      // A tester reads this list back to us verbatim, so it has to be complete in one pass.
      final problems = <String>[];
      expect(StartupConfig.validate({}, problems: problems), isNull);
      expect(problems, ['SUPABASE_URL is not set.', 'SUPABASE_ANON_KEY is not set.']);
    });

    test('names only the key that is actually missing', () {
      final problems = <String>[];
      expect(
        StartupConfig.validate({'SUPABASE_URL': 'https://x.supabase.co'}, problems: problems),
        isNull,
      );
      expect(problems, ['SUPABASE_ANON_KEY is not set.']);
    });

    test('a blank value counts as missing', () {
      // `SUPABASE_URL=` in a copied .env is not configured. Passing '' to Supabase.initialize
      // fails later, further away, with a worse message.
      final problems = <String>[];
      expect(
        StartupConfig.validate(
          {'SUPABASE_URL': '   ', 'SUPABASE_ANON_KEY': ''},
          problems: problems,
        ),
        isNull,
      );
      expect(problems, hasLength(2));
    });
  });

  testWidgets('the error screen shows every problem and needs no app scaffolding', (tester) async {
    // It renders before Supabase, the router and the provider scope exist, so it must not
    // depend on any of them.
    await tester.pumpWidget(const StartupConfigErrorApp(
      problems: ['SUPABASE_URL is not set.', 'SUPABASE_ANON_KEY is not set.'],
    ));
    await tester.pump();

    expect(find.text('This build is not configured'), findsOneWidget);
    expect(find.text('• SUPABASE_URL is not set.'), findsOneWidget);
    expect(find.text('• SUPABASE_ANON_KEY is not set.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

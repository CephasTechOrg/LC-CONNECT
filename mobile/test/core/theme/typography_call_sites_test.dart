import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guard for the type scale.
///
/// Screens used to call `GoogleFonts.dmSans(fontSize: N)` inline — 260 of them across 64 files, at
/// sizes from 9 to 26 including half-steps — so the same kind of text came out a different size on
/// every page. They now use [AppTypography] roles. This keeps it that way: **the font is named in
/// exactly one place**, and a new inline call fails here instead of quietly starting the drift again.
void main() {
  const owner = 'lib/core/theme/app_typography.dart';

  /// The one deliberate exception: inline code in the policy documents needs a monospaced face,
  /// which the app's scale (all DM Sans) does not have.
  const allowed = {'lib/features/policies/widgets/policy_markdown_theme.dart'};

  test('text styles come from AppTypography, never an inline GoogleFonts call', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == owner || allowed.contains(path)) continue;
      if (entity.readAsStringSync().contains('GoogleFonts.')) offenders.add(path);
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use an AppTypography role (display … micro) and copyWith for weight or colour.',
    );
  });

  test('the allowed exception still needs to be one', () {
    for (final path in allowed) {
      expect(File(path).readAsStringSync(), contains('GoogleFonts.robotoMono'),
          reason: '$path no longer uses a non-scale font — drop it from the allowlist');
    }
  });
}

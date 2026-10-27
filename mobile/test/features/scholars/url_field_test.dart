import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/scholars/data/url_field.dart';

/// `normalizeProfileUrl` guards the optional LinkedIn / Handshake fields: blanks clear, scheme-less
/// hosts gain `https://`, and genuine junk is rejected with a field-named message.

void main() {
  group('normalizeProfileUrl', () {
    UrlFieldResult run(String raw) =>
        normalizeProfileUrl(raw, fieldLabel: 'LinkedIn', example: 'linkedin.com/in/you');

    test('blank clears the field', () {
      final r = run('   ');
      expect(r, isA<UrlFieldValid>());
      expect((r as UrlFieldValid).value, '');
    });

    test('a scheme-less host gains https://', () {
      final r = run('linkedin.com/in/jane');
      expect((r as UrlFieldValid).value, 'https://linkedin.com/in/jane');
    });

    test('keeps an existing https scheme', () {
      final r = run('https://linkedin.com/in/jane');
      expect((r as UrlFieldValid).value, 'https://linkedin.com/in/jane');
    });

    test('keeps http as-is', () {
      final r = run('http://example.com/x');
      expect((r as UrlFieldValid).value, 'http://example.com/x');
    });

    test('trims surrounding whitespace', () {
      final r = run('  linkedin.com/in/jane  ');
      expect((r as UrlFieldValid).value, 'https://linkedin.com/in/jane');
    });

    test('rejects a host without a dot', () {
      expect(run('notaurl'), isA<UrlFieldInvalid>());
    });

    test('rejects text with spaces', () {
      expect(run('not a url'), isA<UrlFieldInvalid>());
    });

    test('rejects a non-http scheme', () {
      expect(run('javascript:alert(1)'), isA<UrlFieldInvalid>());
    });

    test('invalid message names the field and the example', () {
      final r = run('nope') as UrlFieldInvalid;
      expect(r.message, contains('LinkedIn'));
      expect(r.message, contains('linkedin.com/in/you'));
    });
  });
}

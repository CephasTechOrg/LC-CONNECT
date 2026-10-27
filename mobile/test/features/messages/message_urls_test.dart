import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/message_urls.dart';

void main() {
  group('firstHttpUrl', () {
    test('finds a bare https URL', () {
      expect(firstHttpUrl('https://example.com/jobs'), 'https://example.com/jobs');
    });

    test('strips a trailing period', () {
      expect(firstHttpUrl('see https://example.com.'), 'https://example.com');
    });

    test('returns null when there is no http(s) URL', () {
      expect(firstHttpUrl('no link here'), isNull);
      expect(firstHttpUrl('ftp://example.com/a'), isNull);
    });

    test('returns the first of several', () {
      expect(
        firstHttpUrl('https://a.com and https://b.com'),
        'https://a.com',
      );
    });
  });

  group('splitMessageLinks', () {
    test('keeps surrounding text and marks the URL', () {
      final runs = splitMessageLinks('see https://example.com/x please');
      expect(runs.map((r) => (r.text, r.isUrl)).toList(), [
        ('see ', false),
        ('https://example.com/x', true),
        (' please', false),
      ]);
    });

    test('plain text is a single run', () {
      final runs = splitMessageLinks('hello');
      expect(runs, hasLength(1));
      expect(runs.single.isUrl, isFalse);
    });
  });
}

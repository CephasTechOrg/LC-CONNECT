import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/data/campus_spotlights.dart';

/// The spotlight card is a **fixed 188dp tall**, and its text sits in a fixed budget:
///
///   16 + 16 padding            -> 156dp usable
///   LIVINGSTONE / COLLEGE      -> ~29dp
///   headline  21sp, w800, h1.14, maxWidth 190  -> 24dp per line
///   gap                        -> 7dp
///   description 11.5sp, h1.4, maxWidth 175     -> ~16dp per line
///
/// Two lines of each leaves comfortable slack. Three lines of description does not, and the
/// card starts crowding the artwork — which is exactly what a 65-character description did.
/// These are character budgets, not a pixel-level layout test: they stop the copy drifting
/// long again, which is the failure that actually happened.
void main() {
  group('spotlight copy stays inside the card', () {
    const maxHeadline = 24; // ~2 lines at 21sp in 190dp
    const maxDescription = 52; // ~2 lines at 11.5sp in 175dp

    for (final s in campusSpotlights) {
      final headline = s.headline
          .map((line) => line.map((w) => w.text).join())
          .join(' ');

      test('"$headline"', () {
        expect(s.headline.length, lessThanOrEqualTo(3),
            reason: 'explicit line breaks past three lines crowd the card');
        for (final line in s.headline) {
          final text = line.map((w) => w.text).join();
          expect(text.length, lessThanOrEqualTo(maxHeadline),
              reason: 'a headline line wraps and pushes the description out');
        }
        expect(s.description.length, lessThanOrEqualTo(maxDescription),
            reason: 'description needs a third line, crowding the card');
        expect(s.studentAsset, isNotNull,
            reason: 'every slide carries its own subject image');
        expect(s.studentLabel, isNotEmpty,
            reason: 'subject images need a semantic label for screen readers');
      });
    }

    test('every subject asset is a declared .webp', () {
      for (final s in campusSpotlights) {
        expect(s.studentAsset, endsWith('.webp'),
            reason: 'PNG photos ship ~20x larger than WebP at this size');
      }
    });

    test('Blue Bear leads, then volleyball, then the cap, and holds 12s', () {
      expect(campusSpotlights.map((s) => s.studentAsset).toList(), [
        'assets/images/lcbear.webp',
        'assets/images/spotlight_student.webp',
        'assets/images/lcgrad.webp',
      ]);
      expect(campusSpotlights.first.dwell, const Duration(seconds: 12));
      expect(campusSpotlights[1].dwell, const Duration(seconds: 10));
      expect(campusSpotlights[2].dwell, const Duration(seconds: 10));
    });
  });
}

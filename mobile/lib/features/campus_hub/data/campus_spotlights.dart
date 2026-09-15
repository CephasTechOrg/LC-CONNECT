/// Home hero spotlights — brand copy that rotates over the campus photo.
///
/// Three slides, one per pillar: community, events, academics. Each carries its own subject
/// image, cut out and feathered into the campus scene by `_FeatheredStudent`.
///
/// The subject slot renders at roughly 198x188 logical px (aspect ~1.05) with `BoxFit.cover`
/// and `Alignment.topCenter`, so a wider source is trimmed at the sides, never top or bottom.
/// **Pre-crop each subject to ~1.05 before exporting.** A four-across group shot left the outer
/// two students sliced in half; two subjects, cropped to the slot aspect, read far better at
/// this size.
library;

class SpotlightWord {
  final String text;
  final bool highlighted;

  const SpotlightWord(this.text, {this.highlighted = false});
}

class CampusSpotlight {
  /// Headline laid out one list per rendered line.
  final List<List<SpotlightWord>> headline;
  final String description;
  final String? studentAsset;
  final String studentLabel;

  const CampusSpotlight({
    required this.headline,
    required this.description,
    this.studentAsset,
    this.studentLabel = '',
  });
}

const campusSpotlightBackground = 'assets/images/spotlight_campus.jpg';

const campusSpotlights = <CampusSpotlight>[
  // 1 — academics. Leads, because it is the reason students are here.
  CampusSpotlight(
    headline: [
      [SpotlightWord('Built for '), SpotlightWord('excellence.', highlighted: true)],
    ],
    description: 'Honors, tutoring, and the push to graduation day.',
    studentAsset: 'assets/images/lcgrad.webp',
    studentLabel: 'Livingstone College graduate holding an LC cap',
  ),
  // 2 — community.
  CampusSpotlight(
    headline: [
      [SpotlightWord('Find your '), SpotlightWord('people.', highlighted: true)],
    ],
    description: 'Join groups built around what you love.',
    studentAsset: 'assets/images/lcgroup.webp',
    studentLabel: 'Livingstone College students together on campus',
  ),
  // 3 — events + athletics.
  CampusSpotlight(
    headline: [
      [SpotlightWord('Never miss a '), SpotlightWord('moment.', highlighted: true)],
    ],
    description: 'Events, games, and study sessions every week.',
    studentAsset: 'assets/images/spotlight_student.webp',
    studentLabel: 'Livingstone College volleyball student-athlete, #14',
  ),
];

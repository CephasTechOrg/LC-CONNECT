/// Home hero spotlights — brand copy over the campus photo, one swipeable slide per feature.
///
/// Three slides, in this order: Blue Bear (community), volleyball (events), grad cap
/// (academics). Each carries its own subject image, cut out and feathered into the campus
/// scene by `_FeatheredStudent`.
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

  /// Where tapping the slide goes — the feature its copy is advertising.
  final String route;

  /// What a screen reader announces for that tap, e.g. "Open groups".
  final String actionLabel;

  const CampusSpotlight({
    required this.headline,
    required this.description,
    required this.route,
    required this.actionLabel,
    this.studentAsset,
    this.studentLabel = '',
  });
}

const campusSpotlightBackground = 'assets/images/spotlight_campus.jpg';

const campusSpotlights = <CampusSpotlight>[
  // 1 — community. Leads: the mascot is the first thing on Home.
  // Three short lines so "Blue Bear" stays together and "family" does not run into the cut-out.
  CampusSpotlight(
    headline: [
      [SpotlightWord('Find your')],
      [SpotlightWord('Blue Bear', highlighted: true)],
      [SpotlightWord('family.', highlighted: true)],
    ],
    description: 'Join groups you love.',
    studentAsset: 'assets/images/lcbear.webp',
    studentLabel: 'Livingstone College Blue Bear mascot',
    // "Join groups you love." — groups live under Messages (`groupsPath`).
    route: '/messages/groups',
    actionLabel: 'Open groups',
  ),
  // 2 — events + athletics.
  CampusSpotlight(
    headline: [
      [SpotlightWord('Never miss a '), SpotlightWord('moment.', highlighted: true)],
    ],
    description: 'Events, games, and study sessions every week.',
    studentAsset: 'assets/images/spotlight_student.webp',
    studentLabel: 'Livingstone College volleyball student-athlete, #1',
    route: '/activities',
    actionLabel: 'Open activities',
  ),
  // 3 — academics.
  CampusSpotlight(
    headline: [
      [SpotlightWord('Built for '), SpotlightWord('excellence.', highlighted: true)],
    ],
    description: 'Honors, tutoring, and the push to graduation day.',
    studentAsset: 'assets/images/lcgrad.webp',
    studentLabel: 'Livingstone College graduate holding an LC cap',
    // Tutoring and academic support live in Resources.
    route: '/home/resources',
    actionLabel: 'Open academic resources',
  ),
];

/// Home hero spotlights — brand copy that rotates over the campus photo.
///
/// Only the first slide carries a student subject image; the rest are the campus
/// scene with copy alone.
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
  CampusSpotlight(
    headline: [
      [SpotlightWord('Stay '), SpotlightWord('connected.', highlighted: true)],
      [SpotlightWord('Stay '), SpotlightWord('involved.', highlighted: true)],
    ],
    description: 'Your campus. Your community. Your future.',
    studentAsset: 'assets/images/spotlight_student.png',
    studentLabel: 'Livingstone College volleyball student-athlete, #14',
  ),
  CampusSpotlight(
    headline: [
      [SpotlightWord('Find your '), SpotlightWord('people.', highlighted: true)],
    ],
    description: 'Join student groups and organizations built around what you love.',
  ),
  CampusSpotlight(
    headline: [
      [SpotlightWord('Never miss a '), SpotlightWord('moment.', highlighted: true)],
    ],
    description: 'Discover campus events, games, and study sessions every week.',
  ),
];

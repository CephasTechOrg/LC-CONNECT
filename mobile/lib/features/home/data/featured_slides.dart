/// Home featured-card slides — image + short copy that rotate together.
library;

class FeaturedSlide {
  final String imageAsset;
  final String badge;
  final String headline;
  final String body;

  const FeaturedSlide({
    required this.imageAsset,
    required this.badge,
    required this.headline,
    required this.body,
  });
}

const featuredSlides = <FeaturedSlide>[
  FeaturedSlide(
    imageAsset: 'assets/images/featured/student_president_optimized.webp',
    badge: 'Welcome to LC Connect',
    headline: 'Lead your campus.\nFind your voice.',
    body: 'Connect with student leaders and shape campus life together.',
  ),
  FeaturedSlide(
    imageAsset: 'assets/images/featured/lab_coat_student_optimized.webp',
    badge: 'Welcome to LC Connect',
    headline: 'Learn together.\nGrow further.',
    body: 'Find study partners and thrive in class — STEM and beyond.',
  ),
  FeaturedSlide(
    imageAsset:
        'assets/images/featured/livingstone_volleyball_hero_optimized.webp',
    badge: 'Welcome to LC Connect',
    headline: 'Play hard.\nCheer louder.',
    body: 'Catch Blue Bear energy and find your crew on and off the court.',
  ),
  FeaturedSlide(
    imageAsset: 'assets/images/featured/tech_student_optimized.webp',
    badge: 'Welcome to LC Connect',
    headline: 'Build skills.\nBuild community.',
    body: 'Meet classmates in tech and collaborate on what comes next.',
  ),
];

/// Wall-clock slot so reopen lands on a varied slide, not always #0.
int featuredSlideIndexAt(DateTime now) {
  const intervalMs = 3 * 60 * 1000;
  final slot = now.millisecondsSinceEpoch ~/ intervalMs;
  return slot % featuredSlides.length;
}

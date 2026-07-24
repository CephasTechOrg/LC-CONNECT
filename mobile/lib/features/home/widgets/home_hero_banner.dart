part of '../screens/home_screen.dart';

class _HeroBanner extends StatefulWidget {
  const _HeroBanner();

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  static const _rotateEvery = Duration(minutes: 3);

  late int _index;
  Timer? _timer;

  FeaturedSlide get _slide => featuredSlides[_index];

  @override
  void initState() {
    super.initState();
    _index = featuredSlideIndexAt(DateTime.now());
    _timer = Timer.periodic(_rotateEvery, (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % featuredSlides.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slide;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: AppColors.primary,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      child: Column(
                        key: ValueKey(_index),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              slide.badge,
                              style: GoogleFonts.dmSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            slide.headline,
                            style: GoogleFonts.dmSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            slide.body,
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () => context.go('/discover'),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                child: Text(
                                  'Get Started',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 118,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        child: Image.asset(
                          slide.imageAsset,
                          key: ValueKey(slide.imageAsset),
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, -0.2),
                          gaplessPlayback: true,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.95),
                              AppColors.primary.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

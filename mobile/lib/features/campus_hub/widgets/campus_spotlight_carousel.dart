part of '../screens/campus_hub_screen.dart';

const _spotlightHeight = 188.0;
const _spotlightRadius = 20.0;

class _SpotlightCarousel extends StatefulWidget {
  const _SpotlightCarousel();

  @override
  State<_SpotlightCarousel> createState() => _SpotlightCarouselState();
}

class _SpotlightCarouselState extends State<_SpotlightCarousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        children: [
          SizedBox(
            height: _spotlightHeight,
            child: PageView.builder(
              controller: _controller,
              itemCount: campusSpotlights.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _SpotlightCard(spotlight: campusSpotlights[i]),
            ),
          ),
          const SizedBox(height: 8),
          _SpotlightDots(
            count: campusSpotlights.length,
            active: _index,
            onTap: (i) => _controller.animateToPage(
              i,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightDots extends StatelessWidget {
  final int count;
  final int active;
  final ValueChanged<int> onTap;

  const _SpotlightDots({
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: EdgeInsets.only(right: i == count - 1 ? 0 : 7),
              width: i == active ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == active ? AppColors.primary : const Color(0xFFC4D3E0),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  final CampusSpotlight spotlight;
  const _SpotlightCard({required this.spotlight});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_spotlightRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x1F245F91), blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_spotlightRadius),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEAF2F9), Color(0xFFD7E6F2)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                campusSpotlightBackground,
                fit: BoxFit.cover,
                alignment: const Alignment(0, 0.1),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1, -0.25),
                    end: Alignment(1, 0.25),
                    stops: [0, 0.4, 0.64, 0.82],
                    colors: [
                      Color(0xF7EEF5FB),
                      Color(0xD1EEF5FB),
                      Color(0x40EEF5FB),
                      Color(0x00EEF5FB),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: -70,
                right: -70,
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x293F7FB5),
                  ),
                ),
              ),
              if (spotlight.studentAsset != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.56,
                    heightFactor: 1,
                    child: _FeatheredStudent(
                      asset: spotlight.studentAsset!,
                      label: spotlight.studentLabel,
                    ),
                  ),
                ),
              const Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: 200,
                  height: 66,
                  child: CustomPaint(painter: _SpotlightCurvePainter()),
                ),
              ),
              _SpotlightContent(spotlight: spotlight),
            ],
          ),
        ),
      ),
    );
  }
}

/// The student subject is a cut-out photo, so it is feathered on the left and
/// bottom edges to blend into the campus scene instead of ending on a hard line.
class _FeatheredStudent extends StatelessWidget {
  final String asset;
  final String label;

  const _FeatheredStudent({required this.asset, required this.label});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: [0, 0.12, 0.95, 1],
        colors: [
          Color(0x00000000),
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0x00000000),
        ],
      ).createShader(bounds),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.06, 1],
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
          ],
        ).createShader(bounds),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          semanticLabel: label.isEmpty ? null : label,
        ),
      ),
    );
  }
}

/// Two stacked brand curves sweeping across the bottom-left of the card.
class _SpotlightCurvePainter extends CustomPainter {
  const _SpotlightCurvePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Paths are authored against a 200x100 grid, then squashed to the card band.
    final sx = size.width / 200;
    final sy = size.height / 100;

    final back = Path()
      ..moveTo(0, 100 * sy)
      ..lineTo(0, 52 * sy)
      ..quadraticBezierTo(70 * sx, 92 * sy, 200 * sx, 100 * sy)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xE6245F91));

    final front = Path()
      ..moveTo(0, 100 * sy)
      ..lineTo(0, 74 * sy)
      ..quadraticBezierTo(54 * sx, 96 * sy, 140 * sx, 100 * sy)
      ..close();
    canvas.drawPath(front, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant _SpotlightCurvePainter oldDelegate) => false;
}

class _SpotlightContent extends StatelessWidget {
  final CampusSpotlight spotlight;
  const _SpotlightContent({required this.spotlight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVINGSTONE',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B2A3A),
              letterSpacing: 0.34,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'COLLEGE',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A4A5A),
              letterSpacing: 3.99,
              height: 1,
            ),
          ),
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text.rich(
              TextSpan(
                children: [
                  for (var line = 0; line < spotlight.headline.length; line++) ...[
                    for (final word in spotlight.headline[line])
                      TextSpan(
                        text: word.text,
                        style: TextStyle(
                          color: word.highlighted ? AppColors.primary : AppColors.textDark,
                        ),
                      ),
                    if (line != spotlight.headline.length - 1) const TextSpan(text: '\n'),
                  ],
                ],
              ),
              style: GoogleFonts.dmSans(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.14,
                letterSpacing: -0.21,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 175),
            child: Text(
              spotlight.description,
              style: GoogleFonts.dmSans(
                fontSize: 11.5,
                color: AppColors.textMid,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

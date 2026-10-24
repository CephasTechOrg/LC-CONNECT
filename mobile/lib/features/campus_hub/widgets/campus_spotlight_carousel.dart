part of '../screens/campus_hub_screen.dart';

const _spotlightHeight = 188.0;

/// The card is a fixed height, but its copy is not: at large accessibility text sizes the
/// headline and description grow past 188dp and overflow. Grow the card with the text instead
/// of clamping the text — clamping would make the one surface a low-vision student most needs
/// to read the one that refuses to scale. Capped so it can't eat the whole viewport.
double _spotlightHeightFor(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
  return _spotlightHeight * scale;
}

const _spotlightRadius = 20.0;

class _SpotlightCarousel extends StatefulWidget {
  const _SpotlightCarousel();

  @override
  State<_SpotlightCarousel> createState() => _SpotlightCarouselState();
}

class _SpotlightCarouselState extends State<_SpotlightCarousel> {
  static const _slide = Duration(milliseconds: 420);

  final _controller = PageController();
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Duration get _dwell => campusSpotlights[_index].dwell;

  void _restartTimer() {
    _timer?.cancel();
    if (campusSpotlights.length < 2) return;
    _timer = Timer(_dwell, _onDwell);
  }

  void _onDwell() {
    if (!mounted) return;
    _advance();
  }

  void _advance() {
    if (!mounted || !_controller.hasClients) return;
    _controller.animateToPage(
      (_index + 1) % campusSpotlights.length,
      duration: _slide,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // An auto-advancing carousel is a known accessibility problem — it moves content out from
    // under someone still reading it. Honour the OS "reduce motion" setting by holding on the
    // first slide and letting them swipe at their own pace.
    if (MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null && campusSpotlights.length > 1) {
      _restartTimer();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      child: Column(
        children: [
          SizedBox(
            height: _spotlightHeightFor(context),
            child: NotificationListener<ScrollNotification>(
              // A deliberate swipe wins: reset the dwell so the slide the student chose gets a
              // full turn instead of sliding away a moment later.
              onNotification: (n) {
                if (n is ScrollStartNotification && n.dragDetails != null) {
                  _timer?.cancel();
                }
                return false;
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: campusSpotlights.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _restartTimer();
                },
                itemBuilder: (_, i) =>
                    _SpotlightCard(spotlight: campusSpotlights[i]),
              ),
            ),
          ),
          // The dots' 32dp hit boxes already add ~12dp of air around them.
          const SizedBox(height: AppSpacing.xs),
          _SpotlightDots(
            count: campusSpotlights.length,
            active: _index,
            onTap: (i) {
              _controller.animateToPage(
                i,
                duration: _slide,
                curve: Curves.easeOutCubic,
              );
            },
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
          // The visible dot is 7dp, but the tap target must not be: wrap it in
          // a 32dp hit box (dots are a supplementary control — the carousel
          // itself swipes — so 32dp here rather than the full 48dp row height).
          Semantics(
            button: true,
            selected: i == active,
            label: 'Show spotlight ${i + 1} of $count',
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: i == active ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == active
                          ? AppColors.primary
                          : const Color(0xFFC4D3E0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
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
          BoxShadow(
            color: Color(0x1F245F91),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
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
          colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000)],
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
    // Copy width follows the card, not a fixed 190dp: on a 320dp phone the
    // student cut-out takes the right ~56%, so fixed widths either collide
    // with it or overflow; on a tablet they strand copy in a narrow column.
    final cardWidth = MediaQuery.sizeOf(context).width - AppSpacing.gutter * 2;
    final copyWidth = (cardWidth * 0.52).clamp(150.0, 220.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        // One cohesive block rather than brand-pinned-top and copy-pinned-bottom. A `Spacer`
        // used to shove the wordmark and the headline to opposite ends of the card, which read
        // as two unrelated things sharing a rectangle instead of one message.
        mainAxisAlignment: MainAxisAlignment.center,
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
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A4A5A),
              letterSpacing: 3.99,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: copyWidth),
            child: Text.rich(
              TextSpan(
                children: [
                  for (
                    var line = 0;
                    line < spotlight.headline.length;
                    line++
                  ) ...[
                    for (final word in spotlight.headline[line])
                      TextSpan(
                        text: word.text,
                        style: TextStyle(
                          color: word.highlighted
                              ? AppColors.primary
                              : AppColors.textDark,
                        ),
                      ),
                    if (line != spotlight.headline.length - 1)
                      const TextSpan(text: '\n'),
                  ],
                ],
              ),
              style: AppTypography.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: copyWidth - 15),
            child: Text(
              spotlight.description,
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w400,
                color: AppColors.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

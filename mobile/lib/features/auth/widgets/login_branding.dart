part of '../screens/login_screen.dart';

/// Full-bleed campus hero with white wave cut into the form below.
class _HeroScene extends StatelessWidget {
  final double height;
  const _HeroScene({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_campus_group.webp',
            fit: BoxFit.cover,
            // Group portrait: faces sit in the upper-middle, so bias up to keep
            // them clear of the wave seam on short phones and when the hero compresses.
            alignment: const Alignment(0, -0.15),
          ),
          // Unlike the old portrait, this photo does not fade to white at the
          // bottom, so paint the fade ourselves — it blends the lower edge (grass)
          // into the form and hides the wave seam.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Color(0x00FFFFFF), AppColors.surface],
                stops: [0.55, 1],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            height: 28,
            child: CustomPaint(painter: _WavePainter()),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.05,
        size.width,
        size.height * 0.65,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.surface);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LcBadge extends StatelessWidget {
  final double size;
  const _LcBadge({this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/lclogo.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

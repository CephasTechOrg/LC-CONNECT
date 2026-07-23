part of '../screens/login_screen.dart';

/// Full-bleed campus hero with white wave cut into the form below.
class _HeroScene extends StatelessWidget {
  const _HeroScene();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/groupstudents.png',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.6),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            height: 40,
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
      'assets/images/lclogo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

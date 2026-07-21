part of '../screens/login_screen.dart';

// ── Branding (logo + title + subtitle) ───────────────────────────
class _Branding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo badge — gradient, Georgia "LC", shadow
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_C.logoTop, _C.logoBot],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x38789DBD),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'LC',
              style: TextStyle(
                fontFamily: 'Georgia',
                color: Colors.white,
                fontSize: 24,
                letterSpacing: -2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.dmSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _C.textDark,
                      height: 1.0,
                      letterSpacing: -1.5,
                    ),
                    children: const [
                      TextSpan(
                        text: 'LC',
                        style: TextStyle(color: _C.primary),
                      ),
                      TextSpan(text: ' Connect'),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Find friends, partners, and activities',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: _C.textMuted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero: school + students + white elliptic curve ────────────────
class _HeroScene extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      margin: const EdgeInsets.only(top: 10),
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          // Students — full-width, pushed down for better head visibility
          Positioned(
            bottom: -80,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/students.png',
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
            ),
          ),
          // Beautiful elliptical curve transition
          Positioned(
            bottom: -50,
            left: -MediaQuery.of(context).size.width * 0.1,
            right: -MediaQuery.of(context).size.width * 0.1,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.elliptical(
                    MediaQuery.of(context).size.width * 0.6,
                    100,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withAlpha(200),
                    blurRadius: 20,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Form section ─────────────────────────────────────────────────

part of '../screens/login_screen.dart';

class _SignInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _SignInButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5A94C2), Color(0xFF3E7EB4)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _C.btnShadow.withAlpha(87),  // .34 opacity
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sign In',
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Continue with school email button ────────────────────────────
class _SchoolEmailButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _C.outlineBdr, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mail_outline_rounded,
                size: 20, color: _C.textBody),
            const SizedBox(width: 12),
            Text(
              'Continue with school email',
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _C.outlineText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Students-only note ────────────────────────────────────────────
class _NoteBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        color: _C.noteBg,
        border: Border.all(color: _C.noteBorder),
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(
            color: Color(0x090F172A),  // ~.035 opacity
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined,
              size: 24, color: _C.noteIconClr),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.dmSans(
                  fontSize: 12.5,
                  color: _C.noteTextClr,
                  height: 1.3,
                ),
                children: [
                  TextSpan(
                    text: 'Students only. ',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w800,
                      color: _C.noteStrong,
                    ),
                  ),
                  const TextSpan(
                    text: 'Verified Livingstone College students can access LC Connect.',
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

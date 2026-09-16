import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

/// The first screen the app shows, held until the stored session has been restored.
///
/// It exists because `/login` was the launch route: the router read `AsyncLoading` as "logged out"
/// and parked authenticated users on a fully interactive login form until `POST /auth/bootstrap`
/// came back. On a cold backend that is not a flash — it is up to a minute of the wrong screen, and
/// users reasonably concluded they had been signed out.
///
/// The login form is not a loading state. This is.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// How long to wait before admitting the wait is unusual.
  static const slowAfter = Duration(seconds: 5);

  /// How long before offering a way out. The API's own connect timeout is 30s and a suspended
  /// free-tier instance can take 30–60s to wake, so a retry offered earlier than this would
  /// usually cancel a request that was about to succeed.
  static const stalledAfter = Duration(seconds: 20);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _slowTimer;
  Timer? _stalledTimer;
  bool _slow = false;
  bool _stalled = false;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(SplashScreen.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
    _stalledTimer = Timer(SplashScreen.stalledAfter, () {
      if (mounted) setState(() => _stalled = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _stalledTimer?.cancel();
    super.dispose();
  }

  /// Rebuilds [AuthNotifier], which re-runs the restore from the stored session.
  ///
  /// Recreating the notifier also resets its "restore finished" flag, so the router keeps us here
  /// until the retry resolves rather than flickering to `/login` and back.
  void _retry() {
    setState(() {
      _slow = false;
      _stalled = false;
    });
    _slowTimer?.cancel();
    _stalledTimer?.cancel();
    _slowTimer = Timer(SplashScreen.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
    _stalledTimer = Timer(SplashScreen.stalledAfter, () {
      if (mounted) setState(() => _stalled = true);
    });
    ref.invalidate(authNotifierProvider);
  }

  @override
  Widget build(BuildContext context) {
    // A restore that has already failed needs no waiting out. `AuthNotifier` throws
    // `AuthRestoreUnreachable` when the backend could not be reached, keeping the session intact
    // — so the retry can be offered the moment that lands, rather than after the timer.
    final failed = ref.watch(authNotifierProvider).hasError;

    // A spinner conveys nothing to a screen reader, and an indeterminate one conveys nothing to
    // anyone after the first few seconds either — so the status is also text, in a live region.
    final stalled = _stalled || failed;
    final status = stalled
        ? "We can't reach LC Connect right now."
        : _slow
            ? 'Still connecting…'
            : 'Signing you in…';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Semantics(
        liveRegion: true,
        label: status,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/lclogo.webp',
                  width: 96,
                  height: 96,
                  // The brand mark is decoration here; the live region above carries the meaning.
                  excludeFromSemantics: true,
                ),
                const SizedBox(height: 28),
                _Indicator(stalled: stalled),
                const SizedBox(height: 18),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMid,
                  ),
                ),
                if (stalled) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Your session is still saved — check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _retry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                    ),
                    child: Text(
                      'Try again',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Progress affordance that does not animate when the viewer has asked for reduced motion.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.stalled});

  final bool stalled;

  @override
  Widget build(BuildContext context) {
    if (stalled) {
      return const Icon(Icons.cloud_off_rounded, size: 26, color: AppColors.textMuted);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      // A spinning indicator is exactly the motion this setting asks us to drop.
      return const Icon(Icons.more_horiz_rounded, size: 26, color: AppColors.primary);
    }
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
    );
  }
}

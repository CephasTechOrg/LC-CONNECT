import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/attendance_provider.dart';
import '../providers/attendance_scanner_provider.dart';
import '../widgets/attendance_result.dart';
import '../widgets/scanner_overlay.dart';

enum _ScannerPhase { loading, scanning, submitting, success, error, permissionDenied }

/// Why the scanner stopped, so recovery can branch on a value instead of on message text.
///
/// Recovery used to be decided by `_errorMessage == 'Attendance is closed.'`. The backend's own
/// 409 detail is `'Attendance is closed'` — no trailing period — so a genuinely closed session
/// matched neither branch and the student got a "Scan again" button that could never succeed.
/// Comparing user-facing prose to choose behaviour is the bug; this enum is the fix.
enum _ScannerError {
  /// Eligibility could not be established (timeout, dropped request). Retrying is meaningful.
  eligibilityUnknown,

  /// Confirmed not permitted. Retrying changes nothing.
  ineligible,

  /// The session is closed. Neither scanning again nor retrying helps.
  closed,

  /// The scanned code was rejected — expired, wrong, or unreadable. Scanning again is the fix.
  badCode,

  /// Check-in failed for some other reason. Worth another attempt.
  checkInFailed,
}

class AttendanceScannerScreen extends ConsumerStatefulWidget {
  const AttendanceScannerScreen({super.key, this.sessionId});

  /// The session the notification was about, when it came from one.
  ///
  /// The push payload has always carried `session_id`, but the tap handler dropped it and the
  /// scanner re-resolved "whatever is active now". That made a tap on a slightly stale
  /// notification report a bare "Attendance is closed" with no hint that the session being
  /// opened was a different, already-finished one.
  final String? sessionId;

  @override
  ConsumerState<AttendanceScannerScreen> createState() => _AttendanceScannerScreenState();
}

class _AttendanceScannerScreenState extends ConsumerState<AttendanceScannerScreen> {
  MobileScannerController? _controller;

  _ScannerPhase _phase = _ScannerPhase.loading;
  _ScannerError? _error;
  String? _errorMessage;
  AttendanceCheckInResult? _result;
  AttendanceSessionInfo? _session;
  bool _handlingScan = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _fail(_ScannerError error, String message) {
    if (!mounted) return;
    setState(() {
      _phase = _ScannerPhase.error;
      _error = error;
      _errorMessage = message;
      _handlingScan = false;
    });
  }

  /// Re-runs the whole entry check. Only offered for [_ScannerError.eligibilityUnknown] — for a
  /// genuine denial or a closed session, retrying cannot change the answer.
  void _retryBootstrap() {
    setState(() {
      _phase = _ScannerPhase.loading;
      _error = null;
      _errorMessage = null;
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Awaited, not read: the sync gate reports `pending` while the membership and feature-flag
    // requests are in flight, and reading it on the first frame flashed "not available for your
    // account" at every scholar before the real answer arrived.
    //
    // A `catch (_) { visible = false; }` used to sit here too, so a cold-start timeout told a
    // genuine Honors scholar the session was not available to them. A failure to *check* is not
    // a denial.
    final bool visible;
    try {
      visible = await ref.read(honorsAttendanceVisibleFutureProvider.future);
    } catch (_) {
      _fail(
        _ScannerError.eligibilityUnknown,
        "We couldn't check your attendance access. Check your connection and try again.",
      );
      return;
    }
    if (!mounted) return;
    if (!visible) {
      _fail(
        _ScannerError.ineligible,
        'This attendance session is not available for your account.',
      );
      return;
    }

    if (!await _ensureCamera()) return;

    try {
      final active = await ref.read(activeAttendanceProvider.future);
      if (!mounted) return;
      if (active.isCheckedIn) {
        setState(() {
          _phase = _ScannerPhase.success;
          _session = active.session;
        });
        return;
      }
      if (!active.open) {
        _fail(_ScannerError.closed, 'Attendance is closed.');
        return;
      }
      // The notification named a session that is no longer the open one. Saying so is far more
      // use than "Attendance is closed" when a different session is in fact open.
      final wanted = widget.sessionId;
      if (wanted != null && active.session != null && active.session!.id != wanted) {
        _fail(
          _ScannerError.closed,
          'That attendance session has closed. A different session is open now — open it from '
              'the Campus tab.',
        );
        return;
      }
      setState(() {
        _session = active.session;
        _controller ??= MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
        );
        _phase = _ScannerPhase.scanning;
      });
    } catch (e) {
      _fail(
        _ScannerError.eligibilityUnknown,
        apiErrorMessage(e, fallback: 'Could not load attendance.'),
      );
    }
  }

  /// Returns true when the camera may be used.
  ///
  /// `isLimited` and `provisional` used to match none of the branches here and fall straight
  /// through, so the scanner mounted without permission and `MobileScanner` failed with nothing
  /// handling it. Anything short of granted is now treated as denied.
  Future<bool> _ensureCamera() async {
    var status = await Permission.camera.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      status = await Permission.camera.request();
    }
    if (!mounted) return false; // the user can back out during the OS prompt
    if (!status.isGranted) {
      setState(() => _phase = _ScannerPhase.permissionDenied);
      return false;
    }
    return true;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_phase != _ScannerPhase.scanning || _handlingScan) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final payload = QrAttendancePayload.tryParse(raw);
    if (payload == null) {
      // Used to `return` silently, so pointing the camera at any other QR code (or a poster, or
      // a URL) looked exactly like a scanner that had stopped working.
      _fail(
        _ScannerError.badCode,
        "That isn't an LC Connect attendance code. Point the camera at the code on the screen.",
      );
      return;
    }

    setState(() {
      _handlingScan = true;
      _phase = _ScannerPhase.submitting;
      _error = null;
      _errorMessage = null;
    });

    try {
      final result = await submitAttendanceCheckIn(ref, payload);
      ref.invalidate(activeAttendanceProvider);
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _ScannerPhase.success;
        _handlingScan = false;
      });
    } catch (e) {
      // HTTP status is the typed signal here — it is already the backend's contract, so it needs
      // no new error-code field and no change to the API surface.
      final status = apiStatusCode(e);
      final message = apiErrorMessage(e, fallback: 'Check-in failed. Try again.');
      _fail(
        switch (status) {
          409 => _ScannerError.closed, // window elapsed or session closed mid-scan
          400 || 410 || 422 => _ScannerError.badCode, // expired / invalid / unparseable code
          _ => _ScannerError.checkInFailed,
        },
        message,
      );
    }
  }

  void _resumeScanning() {
    setState(() {
      _error = null;
      _errorMessage = null;
      _result = null;
      _phase = _ScannerPhase.scanning;
      _handlingScan = false;
    });
  }

  /// What the error screen offers, by cause rather than by message text.
  VoidCallback? get _primaryAction => switch (_error) {
        _ScannerError.eligibilityUnknown => _retryBootstrap,
        _ScannerError.badCode || _ScannerError.checkInFailed => _resumeScanning,
        _ScannerError.closed || _ScannerError.ineligible || null => null,
      };

  VoidCallback? get _dismissAction => switch (_error) {
        _ScannerError.closed || _ScannerError.ineligible => () => context.pop(),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Honors Attendance',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (_phase) {
        _ScannerPhase.loading || _ScannerPhase.submitting =>
          const Center(child: CircularProgressIndicator()),
        _ScannerPhase.permissionDenied => ScannerPermissionPrompt(onOpenSettings: openAppSettings),
        _ScannerPhase.success => AttendanceResultView(
            session: _session,
            result: _result,
            active: ref.watch(activeAttendanceProvider).value,
            onDone: () => context.pop(),
          ),
        _ScannerPhase.error => AttendanceResultView(
            errorMessage: _errorMessage ?? 'Something went wrong.',
            onScanAgain: _primaryAction,
            onDone: _dismissAction,
          ),
        _ScannerPhase.scanning when controller != null => Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: controller, onDetect: _onDetect),
              const ScannerOverlay(),
            ],
          ),
        _ScannerPhase.scanning => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

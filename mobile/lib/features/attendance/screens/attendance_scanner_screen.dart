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

class AttendanceScannerScreen extends ConsumerStatefulWidget {
  const AttendanceScannerScreen({super.key});

  @override
  ConsumerState<AttendanceScannerScreen> createState() => _AttendanceScannerScreenState();
}

class _AttendanceScannerScreenState extends ConsumerState<AttendanceScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  _ScannerPhase _phase = _ScannerPhase.loading;
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
    _controller.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!ref.read(honorsAttendanceVisibleProvider)) {
      setState(() {
        _phase = _ScannerPhase.error;
        _errorMessage = 'This attendance session is not available for your account.';
      });
      return;
    }

    final camera = await Permission.camera.status;
    if (camera.isDenied || camera.isRestricted) {
      final requested = await Permission.camera.request();
      if (!requested.isGranted) {
        setState(() => _phase = _ScannerPhase.permissionDenied);
        return;
      }
    } else if (camera.isPermanentlyDenied) {
      setState(() => _phase = _ScannerPhase.permissionDenied);
      return;
    }

    try {
      final active = await ref.read(activeAttendanceProvider.future);
      if (active.isCheckedIn) {
        setState(() {
          _phase = _ScannerPhase.success;
          _session = active.session;
        });
        return;
      }
      if (!active.open) {
        setState(() {
          _phase = _ScannerPhase.error;
          _errorMessage = 'Attendance is closed.';
        });
        return;
      }
      setState(() {
        _session = active.session;
        _phase = _ScannerPhase.scanning;
      });
    } catch (e) {
      setState(() {
        _phase = _ScannerPhase.error;
        _errorMessage = apiErrorMessage(e, fallback: 'Could not load attendance.');
      });
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_phase != _ScannerPhase.scanning || _handlingScan) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final payload = QrAttendancePayload.tryParse(raw);
    if (payload == null) return;

    setState(() {
      _handlingScan = true;
      _phase = _ScannerPhase.submitting;
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
      if (!mounted) return;
      setState(() {
        _errorMessage = apiErrorMessage(e, fallback: 'Check-in failed. Try again.');
        _phase = _ScannerPhase.error;
        _handlingScan = false;
      });
    }
  }

  void _resumeScanning() {
    setState(() {
      _errorMessage = null;
      _result = null;
      _phase = _ScannerPhase.scanning;
      _handlingScan = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Honors Attendance',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (_phase) {
        _ScannerPhase.loading || _ScannerPhase.submitting => const Center(child: CircularProgressIndicator()),
        _ScannerPhase.permissionDenied => ScannerPermissionPrompt(onOpenSettings: openAppSettings),
        _ScannerPhase.success => AttendanceResultView(
            session: _session,
            result: _result,
            active: ref.watch(activeAttendanceProvider).value,
            onDone: () => context.pop(),
          ),
        _ScannerPhase.error => AttendanceResultView(
            errorMessage: _errorMessage ?? 'Something went wrong.',
            onScanAgain: _errorMessage == 'Attendance is closed.' ? null : _resumeScanning,
            onDone: _errorMessage == 'Attendance is closed.' ? () => context.pop() : null,
          ),
        _ScannerPhase.scanning => Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _controller, onDetect: _onDetect),
              const ScannerOverlay(),
            ],
          ),
      },
    );
  }
}

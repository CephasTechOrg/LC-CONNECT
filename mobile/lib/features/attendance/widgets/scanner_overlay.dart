import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import 'attendance_result.dart';

class ScannerOverlay extends StatelessWidget {
  const ScannerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.45), BlendMode.srcOut),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ),
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 36,
          child: Text(
            'Point your camera at the classroom QR code',
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class ScannerPermissionPrompt extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const ScannerPermissionPrompt({super.key, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return AttendanceMessageLayout(
      badge: const AttendanceBadge(
        icon: Icons.photo_camera_outlined,
        color: AppColors.primaryText,
        tint: AppColors.primarySoft,
      ),
      title: 'Allow camera access',
      message: 'LC Connect uses the camera only to scan the attendance code in class. '
          'Turn it on in Settings, then come back.',
      actionLabel: 'Open settings',
      onAction: onOpenSettings,
    );
  }
}

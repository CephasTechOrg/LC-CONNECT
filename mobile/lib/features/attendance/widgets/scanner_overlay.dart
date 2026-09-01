import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

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
            style: GoogleFonts.dmSans(
              fontSize: 15,
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt_outlined, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 18),
          Text(
            'Camera access is required to scan the attendance QR.',
            style: GoogleFonts.dmSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onOpenSettings, child: const Text('Open Settings')),
        ],
      ),
    );
  }
}

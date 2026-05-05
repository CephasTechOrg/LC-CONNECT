import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activities')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 64, color: AppColors.textMuted),
            SizedBox(height: 16),
            Text('Activities coming soon',
                style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

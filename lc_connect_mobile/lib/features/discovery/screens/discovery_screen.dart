import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppColors.textMuted),
            SizedBox(height: 16),
            Text('Discovery coming soon',
                style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import 'staff_onboarding_screen.dart';
import 'student_onboarding_screen.dart';

/// Routes verified users to the correct onboarding flow for their server-assigned role.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authNotifierProvider).asData?.value?.role ?? 'student';
    if (role == 'staff') return const StaffOnboardingScreen();
    return const StudentOnboardingScreen();
  }
}

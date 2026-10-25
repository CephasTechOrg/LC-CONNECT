import '../../auth/providers/auth_provider.dart';

/// What onboarding pre-fills as the display name: the name given at signup, or — for accounts made
/// before signup asked for one — a guess from the campus address ("ama.mensah" → "Ama Mensah").
///
/// Student and staff onboarding each carried their own copy of the address guess.
String suggestedDisplayName(AuthUser user) {
  final first = user.firstName?.trim() ?? '';
  final last = user.lastName?.trim() ?? '';
  if (first.isNotEmpty && last.isNotEmpty) return '$first $last';
  return user.email
      .split('@')
      .first
      .replaceAll(RegExp(r'[._\-]'), ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ')
      .trim();
}

/// The onboarding header's title: "Welcome, Ama" when signup gave a first name, else [fallback].
String onboardingWelcome(AuthUser? user, {required String fallback}) {
  final first = user?.firstName?.trim() ?? '';
  return first.isEmpty ? fallback : 'Welcome, $first';
}

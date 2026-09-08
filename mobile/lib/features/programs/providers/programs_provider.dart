import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';

/// The slug for the one program that exists today — Blueprint Bond surfaces key off this.
const presidentialScholarsSlug = 'presidential_scholars';

class ProgramMembership {
  final String id;
  final String userId;
  final String status; // active | revoked
  final String programSlug;
  final String programName;

  const ProgramMembership({
    required this.id,
    required this.userId,
    required this.status,
    required this.programSlug,
    required this.programName,
  });

  factory ProgramMembership.fromJson(Map<String, dynamic> j) => ProgramMembership(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        status: j['status'] as String,
        programSlug: j['program_slug'] as String,
        programName: j['program_name'] as String,
      );

  bool get isActive => status == 'active';
}

/// Every program this user is currently an active member of (server only ever returns active
/// rows — see `GET /programs/me`).
///
/// Kept alive (not autoDispose): Campus Hub remounts often on tab/nav, and disposing this made
/// [isVerifiedScholarProvider] flip false→true while reloading — the Blueprint Bond prompt
/// blinked off and on every time the student came back to Home.
final myProgramMembershipsProvider = FutureProvider<List<ProgramMembership>>((ref) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/programs/me');
  return (response.data as List)
      .map((j) => ProgramMembership.fromJson(j as Map<String, dynamic>))
      .toList();
});

/// Whether the current user is a verified Presidential Scholar — drives every Blueprint Bond
/// surface (completion card, professional-profile screen access).
final isVerifiedScholarProvider = Provider<bool>((ref) {
  final memberships = ref.watch(myProgramMembershipsProvider);
  // Prefer the last known list while a refresh is in flight so the prompt doesn't vanish.
  final list = memberships.asData?.value ?? memberships.value ?? const <ProgramMembership>[];
  return list.any((m) => m.programSlug == presidentialScholarsSlug && m.isActive);
});

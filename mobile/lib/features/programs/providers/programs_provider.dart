import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/util/eligibility.dart';
import '../../../shared/util/keep_fresh.dart';
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
/// [scholarEligibilityProvider] flip false→true while reloading — the Blueprint Bond prompt
/// blinked off and on every time the student came back to Home.
///
/// Being kept alive is also why it needs [keepFresh]: it re-runs only when `authNotifierProvider`
/// changes identity, so without this a single failure at launch stuck for the whole session and
/// took four gated surfaces down with it (see [Eligibility]).
final myProgramMembershipsProvider = FutureProvider<List<ProgramMembership>>((ref) async {
  keepFresh(ref, onStale: ref.invalidateSelf);
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/programs/me');
  return (response.data as List)
      .map((j) => ProgramMembership.fromJson(j as Map<String, dynamic>))
      .toList();
});

/// Awaitable form of [scholarEligibilityProvider].
///
/// The sync one reports [Eligibility.pending] while the membership list is still loading, which is
/// correct for *rendering* — a surface that hasn't been shown yet shouldn't flash in. Code that
/// makes a *decision* needs the real answer, so it awaits this instead and handles the throw:
/// the attendance scanner used to read the sync form on its first frame and show "not available
/// for your account" before the request had even returned.
///
/// This **throws** on failure rather than returning `false`. Callers must catch and report
/// "couldn't check" — never "not permitted".
final isVerifiedScholarFutureProvider = FutureProvider<bool>((ref) async {
  final memberships = await ref.watch(myProgramMembershipsProvider.future);
  return memberships.any((m) => m.programSlug == presidentialScholarsSlug && m.isActive);
});

/// Whether the current user is a verified Presidential Scholar — drives every Blueprint Bond
/// surface (completion card, professional-profile screen access), Honors attendance, and the
/// scholar filter on Campus Opportunities.
///
/// Replaces a `Provider<bool>` that fell back to `const []` on `AsyncError` and so reported a
/// confident "not a scholar" whenever `GET /programs/me` failed. [eligibilityFrom] keeps the
/// no-flicker behaviour (a stale-but-known answer still wins mid-refresh) while surfacing failure
/// as [Eligibility.unknown].
final scholarEligibilityProvider = Provider<Eligibility>((ref) {
  return eligibilityFrom(
    ref.watch(myProgramMembershipsProvider),
    (list) => list.any((m) => m.programSlug == presidentialScholarsSlug && m.isActive),
  );
});

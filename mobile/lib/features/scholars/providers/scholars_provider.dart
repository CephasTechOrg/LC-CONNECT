import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/util/keep_fresh.dart';
import '../../auth/providers/auth_provider.dart';

class ScholarProfile {
  final String id;
  final String userId;
  final String? linkedinUrl;
  final String? handshakeUrl;
  final String? summary;
  final List<String> skills;
  final List<String> careerInterests;
  final bool employerVisibilityConsent;
  final bool hasHeadshot;
  final bool hasResume;

  /// Server-owned. The client must never re-derive this: the rule includes a minimum summary
  /// length and employer consent, and a second definition here would drift from the one the
  /// admin and employer views use. See `missing_profile_fields` in the backend service.
  final bool isComplete;

  /// API field names still outstanding, in the order a student would fill them — lets the prompt
  /// name what is left instead of nudging generically.
  final List<String> missingFields;

  const ScholarProfile({
    required this.id,
    required this.userId,
    this.linkedinUrl,
    this.handshakeUrl,
    this.summary,
    required this.skills,
    required this.careerInterests,
    required this.employerVisibilityConsent,
    required this.hasHeadshot,
    required this.hasResume,
    required this.isComplete,
    required this.missingFields,
  });

  factory ScholarProfile.fromJson(Map<String, dynamic> j) => ScholarProfile(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        linkedinUrl: j['linkedin_url'] as String?,
        handshakeUrl: j['handshake_url'] as String?,
        summary: j['summary'] as String?,
        skills: List<String>.from(j['skills'] ?? []),
        careerInterests: List<String>.from(j['career_interests'] ?? []),
        employerVisibilityConsent: j['employer_visibility_consent'] as bool? ?? false,
        hasHeadshot: j['has_headshot'] as bool? ?? false,
        hasResume: j['has_resume'] as bool? ?? false,
        // Absent means an older server. Defaulting to *incomplete* keeps the prompt visible,
        // which is the safe failure: a student is nudged about a profile that may be finished,
        // rather than silently never nudged about one that is not.
        isComplete: j['is_complete'] as bool? ?? false,
        missingFields: List<String>.from(j['missing_fields'] ?? const <String>[]),
      );
}

final scholarProfileNotifierProvider =
    AsyncNotifierProvider<ScholarProfileNotifier, ScholarProfile>(ScholarProfileNotifier.new);

class ScholarProfileNotifier extends AsyncNotifier<ScholarProfile> {
  @override
  Future<ScholarProfile> build() async {
    // A failure here used to hide the Blueprint Bond dashboard prompt with no error and no way
    // back: nothing in the app invalidated this notifier, so it re-ran only when the signed-in
    // identity changed. See [keepFresh].
    keepFresh(ref, onStale: ref.invalidateSelf);
    ref.watch(authNotifierProvider);
    final client = ref.watch(apiClientProvider);
    final response = await client.dio.get('/scholars/me');
    return ScholarProfile.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> updateFields({
    String? linkedinUrl,
    String? handshakeUrl,
    String? summary,
    List<String>? skills,
    List<String>? careerInterests,
  }) async {
    final client = ref.read(apiClientProvider);
    final body = <String, dynamic>{
      if (linkedinUrl != null) 'linkedin_url': linkedinUrl,
      if (handshakeUrl != null) 'handshake_url': handshakeUrl,
      if (summary != null) 'summary': summary,
      if (skills != null) 'skills': skills,
      if (careerInterests != null) 'career_interests': careerInterests,
    };
    final response = await client.dio.patch('/scholars/me', data: body);
    state = AsyncData(ScholarProfile.fromJson(response.data as Map<String, dynamic>));
  }

  Future<void> setConsent(bool consent) async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.post('/scholars/me/consent', data: {'consent': consent});
    state = AsyncData(ScholarProfile.fromJson(response.data as Map<String, dynamic>));
  }

  Future<void> uploadHeadshot({
    required String path,
    required String mimeType,
    required String filename,
  }) async {
    final client = ref.read(apiClientProvider);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename, contentType: DioMediaType.parse(mimeType)),
    });
    final response = await client.dio.post(
      '/scholars/me/headshot',
      data: formData,
      // Uploads need far longer than the default: a multi-MB body over mobile data, then
      // server-side image sanitising and an object-storage round trip before any response.
      options: Options(
        sendTimeout: AppConstants.uploadTimeout,
        receiveTimeout: AppConstants.uploadTimeout,
      ),
    );
    state = AsyncData(ScholarProfile.fromJson(response.data as Map<String, dynamic>));
  }

  Future<void> uploadResume({
    required String path,
    required String mimeType,
    required String filename,
  }) async {
    final client = ref.read(apiClientProvider);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename, contentType: DioMediaType.parse(mimeType)),
    });
    final response = await client.dio.post(
      '/scholars/me/resume',
      data: formData,
      options: Options(
        sendTimeout: AppConstants.uploadTimeout,
        receiveTimeout: AppConstants.uploadTimeout,
      ),
    );
    state = AsyncData(ScholarProfile.fromJson(response.data as Map<String, dynamic>));
  }

  Future<String> headshotUrl() async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.get('/scholars/me/headshot-url');
    return (response.data as Map<String, dynamic>)['url'] as String;
  }

  Future<String> resumeUrl() async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.get('/scholars/me/resume-url');
    return (response.data as Map<String, dynamic>)['url'] as String;
  }
}

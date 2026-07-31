import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
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
      );
}

final scholarProfileNotifierProvider =
    AsyncNotifierProvider<ScholarProfileNotifier, ScholarProfile>(ScholarProfileNotifier.new);

class ScholarProfileNotifier extends AsyncNotifier<ScholarProfile> {
  @override
  Future<ScholarProfile> build() async {
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
    final response = await client.dio.post('/scholars/me/headshot', data: formData);
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
    final response = await client.dio.post('/scholars/me/resume', data: formData);
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

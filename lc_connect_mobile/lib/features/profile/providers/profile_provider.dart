import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';

// ── Public profile (viewing another user) ─────────────────────────

class PublicProfile {
  final String profileId;
  final String userId;
  final String? displayName;
  final String? pronouns;
  final String? major;
  final int? classYear;
  final String? countryState;
  final String? campus;
  final String? bio;
  final String? avatarUrl;
  final List<String> interests;
  final List<String> languagesSpoken;
  final List<String> languagesLearning;
  final List<String> lookingFor;
  final bool isVerified;

  const PublicProfile({
    required this.profileId,
    required this.userId,
    this.displayName,
    this.pronouns,
    this.major,
    this.classYear,
    this.countryState,
    this.campus,
    this.bio,
    this.avatarUrl,
    required this.interests,
    required this.languagesSpoken,
    required this.languagesLearning,
    required this.lookingFor,
    required this.isVerified,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> j) => PublicProfile(
        profileId: j['id'] as String,
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String?,
        pronouns: j['pronouns'] as String?,
        major: j['major'] as String?,
        classYear: j['class_year'] as int?,
        countryState: j['country_state'] as String?,
        campus: j['campus'] as String?,
        bio: j['bio'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        interests: List<String>.from(j['interests'] ?? []),
        languagesSpoken: List<String>.from(j['languages_spoken'] ?? []),
        languagesLearning: List<String>.from(j['languages_learning'] ?? []),
        lookingFor: List<String>.from(j['looking_for'] ?? []),
        isVerified: j['is_verified'] as bool? ?? false,
      );
}

final publicProfileProvider =
    FutureProvider.family<PublicProfile, String>((ref, profileId) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/profiles/$profileId');
  return PublicProfile.fromJson(response.data as Map<String, dynamic>);
});

// ── My profile ────────────────────────────────────────────────────

class MyProfile {
  final String profileId;
  final String userId;
  final String? displayName;
  final String? pronouns;
  final String? major;
  final int? classYear;
  final String? countryState;
  final String? campus;
  final String? bio;
  final String? avatarUrl;
  final bool isHidden;
  final bool isVerified;
  final bool profileCompleted;
  final List<String> interests;
  final List<String> languagesSpoken;
  final List<String> languagesLearning;
  final List<String> lookingFor;
  final List<String> lookingForCodes;
  final bool allowMessagesFromMatchesOnly;
  final bool showProfileToVerifiedOnly;
  final int connectionCount;
  final int activityCount;
  final int messageCount;

  const MyProfile({
    required this.profileId,
    required this.userId,
    this.displayName,
    this.pronouns,
    this.major,
    this.classYear,
    this.countryState,
    this.campus,
    this.bio,
    this.avatarUrl,
    required this.isHidden,
    required this.isVerified,
    required this.profileCompleted,
    required this.interests,
    required this.languagesSpoken,
    required this.languagesLearning,
    required this.lookingFor,
    required this.lookingForCodes,
    required this.allowMessagesFromMatchesOnly,
    required this.showProfileToVerifiedOnly,
    required this.connectionCount,
    required this.activityCount,
    required this.messageCount,
  });

  factory MyProfile.fromJson(Map<String, dynamic> j) => MyProfile(
        profileId: j['id'] as String,
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String?,
        pronouns: j['pronouns'] as String?,
        major: j['major'] as String?,
        classYear: j['class_year'] as int?,
        countryState: j['country_state'] as String?,
        campus: j['campus'] as String?,
        bio: j['bio'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        isHidden: j['is_hidden'] as bool? ?? false,
        isVerified: j['is_verified'] as bool? ?? false,
        profileCompleted: j['profile_completed'] as bool? ?? false,
        interests: List<String>.from(j['interests'] ?? []),
        languagesSpoken: List<String>.from(j['languages_spoken'] ?? []),
        languagesLearning: List<String>.from(j['languages_learning'] ?? []),
        lookingFor: List<String>.from(j['looking_for'] ?? []),
        lookingForCodes: List<String>.from(j['looking_for_codes'] ?? []),
        allowMessagesFromMatchesOnly:
            j['allow_messages_from_matches_only'] as bool? ?? true,
        showProfileToVerifiedOnly:
            j['show_profile_to_verified_only'] as bool? ?? true,
        connectionCount: (j['connection_count'] as num?)?.toInt() ?? 0,
        activityCount: (j['activity_count'] as num?)?.toInt() ?? 0,
        messageCount: (j['message_count'] as num?)?.toInt() ?? 0,
      );

  MyProfile copyWith({
    bool? allowMessagesFromMatchesOnly,
    bool? showProfileToVerifiedOnly,
  }) =>
      MyProfile(
        profileId: profileId,
        userId: userId,
        displayName: displayName,
        pronouns: pronouns,
        major: major,
        classYear: classYear,
        countryState: countryState,
        campus: campus,
        bio: bio,
        avatarUrl: avatarUrl,
        isHidden: isHidden,
        isVerified: isVerified,
        profileCompleted: profileCompleted,
        interests: interests,
        languagesSpoken: languagesSpoken,
        languagesLearning: languagesLearning,
        lookingFor: lookingFor,
        lookingForCodes: lookingForCodes,
        allowMessagesFromMatchesOnly:
            allowMessagesFromMatchesOnly ?? this.allowMessagesFromMatchesOnly,
        showProfileToVerifiedOnly:
            showProfileToVerifiedOnly ?? this.showProfileToVerifiedOnly,
        connectionCount: connectionCount,
        activityCount: activityCount,
        messageCount: messageCount,
      );
}

// ── Provider ──────────────────────────────────────────────────────
final myProfileNotifierProvider =
    AsyncNotifierProvider<MyProfileNotifier, MyProfile>(
        MyProfileNotifier.new);

class MyProfileNotifier extends AsyncNotifier<MyProfile> {
  @override
  Future<MyProfile> build() async {
    ref.watch(authNotifierProvider);
    final client = ref.watch(apiClientProvider);
    final response = await client.dio.get('/profiles/me');
    return MyProfile.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> uploadAvatar({
    required String path,
    required String mimeType,
    required String filename,
  }) async {
    final client = ref.read(apiClientProvider);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    await client.dio.post('/profiles/me/avatar', data: formData);
    ref.invalidateSelf();
  }

  Future<void> updateProfile({
    required String displayName,
    required String major,
    String? pronouns,
    int? classYear,
    String? countryState,
    String? campus,
    String? bio,
    required List<String> interests,
    required List<String> languagesSpoken,
    required List<String> languagesLearning,
    required List<String> lookingForCodes,
  }) async {
    final client = ref.read(apiClientProvider);
    final body = <String, dynamic>{
      'display_name': displayName,
      'major': major,
      'interests': interests,
      'languages_spoken': languagesSpoken,
      'languages_learning': languagesLearning,
      'looking_for_codes': lookingForCodes,
    };
    if (pronouns != null && pronouns.isNotEmpty) body['pronouns'] = pronouns;
    if (classYear != null) body['class_year'] = classYear;
    if (countryState != null && countryState.isNotEmpty) {
      body['country_state'] = countryState;
    }
    if (campus != null && campus.isNotEmpty) body['campus'] = campus;
    if (bio != null && bio.isNotEmpty) body['bio'] = bio;
    await client.dio.patch('/profiles/me', data: body);
    ref.invalidateSelf();
  }

  Future<void> updatePreference({
    bool? allowMessagesFromMatchesOnly,
    bool? showProfileToVerifiedOnly,
  }) async {
    // Optimistic update
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(
        allowMessagesFromMatchesOnly: allowMessagesFromMatchesOnly,
        showProfileToVerifiedOnly: showProfileToVerifiedOnly,
      ));
    }
    try {
      final client = ref.read(apiClientProvider);
      final body = <String, dynamic>{};
      if (allowMessagesFromMatchesOnly != null) {
        body['allow_messages_from_matches_only'] = allowMessagesFromMatchesOnly;
      }
      if (showProfileToVerifiedOnly != null) {
        body['show_profile_to_verified_only'] = showProfileToVerifiedOnly;
      }
      await client.dio.patch('/profiles/me', data: body);
    } catch (e) {
      // Roll back on failure
      if (current != null) state = AsyncData(current);
      rethrow;
    }
  }
}

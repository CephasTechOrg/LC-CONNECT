import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';

class LookupData {
  final List<String> interests;
  final List<String> languages;
  final List<Map<String, String>> lookingFor; // [{code, name}]

  const LookupData({
    required this.interests,
    required this.languages,
    required this.lookingFor,
  });
}

final lookupDataProvider = FutureProvider<LookupData>((ref) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/lookups');
  final data = response.data as Map<String, dynamic>;
  return LookupData(
    interests: (data['interests'] as List)
        .map((i) => i['name'] as String)
        .toList(),
    languages: (data['languages'] as List)
        .map((l) => l['name'] as String)
        .toList(),
    lookingFor: (data['looking_for'] as List)
        .map((l) => {'code': l['code'] as String, 'name': l['name'] as String})
        .toList(),
  );
});

final onboardingNotifierProvider =
    AsyncNotifierProvider<OnboardingNotifier, void>(OnboardingNotifier.new);

class OnboardingNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit({
    required String displayName,
    String? pronouns,
    required String major,
    required int classYear,
    String? countryState,
    String? bio,
    required List<String> interests,
    required List<String> languagesSpoken,
    required List<String> languagesLearning,
    required List<String> lookingForCodes,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(apiClientProvider);
      final body = <String, dynamic>{
        'display_name': displayName,
        'major': major,
        'class_year': classYear,
        'interests': interests,
        'languages_spoken': languagesSpoken,
        'languages_learning': languagesLearning,
        'looking_for_codes': lookingForCodes,
      };
      if (pronouns != null && pronouns.isNotEmpty) body['pronouns'] = pronouns;
      if (countryState != null && countryState.isNotEmpty) body['country_state'] = countryState;
      if (bio != null && bio.isNotEmpty) body['bio'] = bio;
      await client.dio.patch('/profiles/me', data: body);
    });
  }
}

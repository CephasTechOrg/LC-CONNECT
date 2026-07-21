import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';

class DiscoveryCard {
  final String profileId;
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String? major;
  final int? classYear;
  final String? bio;
  final List<String> interests;
  final List<String> languagesSpoken;
  final List<String> languagesLearning;
  final List<String> lookingFor;
  final List<String> lookingForCodes;
  final int matchScore;
  final List<String> matchReasons;

  const DiscoveryCard({
    required this.profileId,
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.major,
    this.classYear,
    this.bio,
    required this.interests,
    required this.languagesSpoken,
    required this.languagesLearning,
    required this.lookingFor,
    required this.lookingForCodes,
    required this.matchScore,
    required this.matchReasons,
  });

  factory DiscoveryCard.fromJson(Map<String, dynamic> j) => DiscoveryCard(
        profileId: j['profile_id'] as String,
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        major: j['major'] as String?,
        classYear: j['class_year'] as int?,
        bio: j['bio'] as String?,
        interests: List<String>.from(j['interests'] ?? []),
        languagesSpoken: List<String>.from(j['languages_spoken'] ?? []),
        languagesLearning: List<String>.from(j['languages_learning'] ?? []),
        lookingFor: List<String>.from(j['looking_for'] ?? []),
        lookingForCodes: List<String>.from(j['looking_for_codes'] ?? []),
        matchScore: (j['match_score'] as num?)?.toInt() ?? 0,
        matchReasons: List<String>.from(j['match_reasons'] ?? []),
      );
}

final discoveryNotifierProvider =
    AsyncNotifierProvider<DiscoveryNotifier, List<DiscoveryCard>>(
        DiscoveryNotifier.new);

class DiscoveryNotifier extends AsyncNotifier<List<DiscoveryCard>> {
  @override
  Future<List<DiscoveryCard>> build() async {
    ref.watch(authNotifierProvider);
    final client = ref.watch(apiClientProvider);
    final response = await client.dio.get('/discovery/cards');
    return (response.data as List)
        .map((j) => DiscoveryCard.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // Remove a card locally without an API call (Maybe Later).
  void skip(String profileId) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(current.where((c) => c.profileId != profileId).toList());
  }

  // Send a connection request then remove the card on success.
  Future<void> connect(
      String userId, String profileId, String intent) async {
    final client = ref.read(apiClientProvider);
    await client.dio.post('/connections/request', data: {
      'receiver_id': userId,
      'intent': intent,
    });
    skip(profileId);
  }
}

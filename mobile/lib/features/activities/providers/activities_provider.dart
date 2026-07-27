import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';

class Activity {
  final String id;
  final String creatorId;
  final String title;
  final String? description;
  final String category;
  final String location;
  final String? bannerUrl;
  final DateTime startTime;
  final DateTime? endTime;
  final int? maxParticipants;
  final int participantCount;
  final bool hasJoined;

  const Activity({
    required this.id,
    required this.creatorId,
    required this.title,
    this.description,
    required this.category,
    required this.location,
    this.bannerUrl,
    required this.startTime,
    this.endTime,
    this.maxParticipants,
    required this.participantCount,
    required this.hasJoined,
  });

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: j['id'] as String,
        creatorId: j['creator_id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        category: j['category'] as String,
        location: j['location'] as String,
        bannerUrl: j['banner_url'] as String?,
        startTime: DateTime.parse(j['start_time'] as String),
        endTime:
            j['end_time'] != null ? DateTime.parse(j['end_time'] as String) : null,
        maxParticipants: j['max_participants'] as int?,
        participantCount: (j['participant_count'] as num?)?.toInt() ?? 0,
        hasJoined: j['has_joined'] as bool? ?? false,
      );

  Activity copyWith({int? participantCount, bool? hasJoined}) => Activity(
        id: id,
        creatorId: creatorId,
        title: title,
        description: description,
        category: category,
        location: location,
        bannerUrl: bannerUrl,
        startTime: startTime,
        endTime: endTime,
        maxParticipants: maxParticipants,
        participantCount: participantCount ?? this.participantCount,
        hasJoined: hasJoined ?? this.hasJoined,
      );
}

/// A row in an activity's roster (public — names + avatars, no moderation).
class ActivityParticipant {
  final String userId;
  final String? profileId;
  final String? displayName;
  final String? avatarUrl;
  final bool isCreator;

  const ActivityParticipant({
    required this.userId,
    this.profileId,
    this.displayName,
    this.avatarUrl,
    required this.isCreator,
  });

  factory ActivityParticipant.fromJson(Map<String, dynamic> j) => ActivityParticipant(
        userId: j['user_id'] as String,
        profileId: j['profile_id'] as String?,
        displayName: j['display_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        isCreator: j['is_creator'] as bool? ?? false,
      );

  String get name => displayName ?? 'LC Student';
}

/// The roster for one activity.
final activityParticipantsProvider =
    FutureProvider.autoDispose.family<List<ActivityParticipant>, String>((ref, activityId) async {
  final resp = await ref.read(apiClientProvider).dio.get('/activities/$activityId/participants');
  return (resp.data as List)
      .map((j) => ActivityParticipant.fromJson(j as Map<String, dynamic>))
      .toList();
});

class ActivitiesFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all';
  void set(String filter) => state = filter;
}

final activitiesFilterProvider =
    NotifierProvider<ActivitiesFilterNotifier, String>(ActivitiesFilterNotifier.new);

final activitiesNotifierProvider =
    AsyncNotifierProvider<ActivitiesNotifier, List<Activity>>(
        ActivitiesNotifier.new);

class ActivitiesNotifier extends AsyncNotifier<List<Activity>> {
  @override
  Future<List<Activity>> build() async {
    ref.watch(authNotifierProvider);
    final filter = ref.watch(activitiesFilterProvider);
    final client = ref.watch(apiClientProvider);
    final params = filter == 'all' ? null : {'category': filter};
    final response =
        await client.dio.get('/activities', queryParameters: params);
    return (response.data as List)
        .map((j) => Activity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> join(String activityId) async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.post('/activities/$activityId/join');
    _updateOne(Activity.fromJson(response.data as Map<String, dynamic>));
  }

  Future<void> leave(String activityId) async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.delete('/activities/$activityId/leave');
    _updateOne(Activity.fromJson(response.data as Map<String, dynamic>));
  }

  Future<Activity> create({
    required String title,
    required String category,
    required String location,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    int? maxParticipants,
  }) async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.post('/activities', data: {
      'title': title.trim(),
      'category': category,
      'location': location.trim(),
      'start_time': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'end_time': endTime.toUtc().toIso8601String(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      'max_participants': ?maxParticipants,
    });
    final created = Activity.fromJson(response.data as Map<String, dynamic>);
    final current = state.asData?.value ?? [];
    state = AsyncData([created, ...current]);
    return created;
  }

  /// Edit (creator-only) — sends only the changed fields (PATCH). Returns the updated activity.
  Future<Activity> edit(String activityId, Map<String, dynamic> changes) async {
    final client = ref.read(apiClientProvider);
    final response = await client.dio.patch('/activities/$activityId', data: changes);
    final updated = Activity.fromJson(response.data as Map<String, dynamic>);
    _updateOne(updated);
    return updated;
  }

  /// Cancel (creator-only). The activity drops out of the list on next refresh.
  Future<void> cancel(String activityId) async {
    await ref.read(apiClientProvider).dio.post('/activities/$activityId/cancel');
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.where((a) => a.id != activityId).toList());
    }
  }

  /// Upload/replace the banner (creator-only). Returns the updated activity.
  Future<Activity> uploadBanner(
    String activityId, {
    required String path,
    required String mimeType,
    required String filename,
  }) async {
    final client = ref.read(apiClientProvider);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename, contentType: DioMediaType.parse(mimeType)),
    });
    final response = await client.dio.post('/activities/$activityId/banner', data: formData);
    final updated = Activity.fromJson(response.data as Map<String, dynamic>);
    _updateOne(updated);
    return updated;
  }

  void _updateOne(Activity updated) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(
        current.map((a) => a.id == updated.id ? updated : a).toList());
  }
}

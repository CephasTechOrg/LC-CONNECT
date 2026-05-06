import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';

class Activity {
  final String id;
  final String creatorId;
  final String title;
  final String? description;
  final String category;
  final String location;
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
        startTime: startTime,
        endTime: endTime,
        maxParticipants: maxParticipants,
        participantCount: participantCount ?? this.participantCount,
        hasJoined: hasJoined ?? this.hasJoined,
      );
}

class _FilterNotifier extends Notifier<String> {
  @override
  String build() => 'all';
  void set(String filter) => state = filter;
}

final activitiesFilterProvider =
    NotifierProvider<_FilterNotifier, String>(_FilterNotifier.new);

final activitiesNotifierProvider =
    AsyncNotifierProvider<ActivitiesNotifier, List<Activity>>(
        ActivitiesNotifier.new);

class ActivitiesNotifier extends AsyncNotifier<List<Activity>> {
  @override
  Future<List<Activity>> build() async {
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

  void _updateOne(Activity updated) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(
        current.map((a) => a.id == updated.id ? updated : a).toList());
  }
}

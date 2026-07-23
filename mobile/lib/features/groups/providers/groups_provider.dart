import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/group_models.dart';

/// Backend category filters. The UI's friendly chips map onto these.
const groupApiCategories = {
  'Academic': 'class',
  'Clubs & Sports': 'club',
  'Housing': 'housing',
  'Wellness': 'interest',
  'Career': 'interest',
  'Creative': 'interest',
};

class GroupsRepository {
  GroupsRepository(this._ref);
  final Ref _ref;

  Future<List<GroupSummary>> discover({String? category, String? query}) async {
    final dio = _ref.read(apiClientProvider).dio;
    final params = <String, dynamic>{};
    if (category != null) params['category'] = category;
    if (query != null && query.isNotEmpty) params['q'] = query;
    final resp = await dio.get('/groups/discover', queryParameters: params);
    return (resp.data as List)
        .map((j) => GroupSummary.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<GroupSummary>> myGroups() async {
    final dio = _ref.read(apiClientProvider).dio;
    final resp = await dio.get('/groups/me');
    return (resp.data as List)
        .map((j) => GroupSummary.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Returns the resulting status: `active` (joined) or `requested` (awaiting approval).
  Future<String> join(String groupId) async {
    final dio = _ref.read(apiClientProvider).dio;
    final resp = await dio.post('/groups/$groupId/join');
    return (resp.data as Map<String, dynamic>)['status'] as String;
  }

  Future<GroupRead> create({
    required String name,
    required String category,
    String visibility = 'public',
    String joinPolicy = 'open',
    String? description,
    int? maxMembers,
  }) async {
    final dio = _ref.read(apiClientProvider).dio;
    final data = <String, dynamic>{
      'name': name,
      'category': category,
      'visibility': visibility,
      'join_policy': joinPolicy,
    };
    if (description != null && description.isNotEmpty) data['description'] = description;
    if (maxMembers != null) data['max_members'] = maxMembers;
    final resp = await dio.post('/groups', data: data);
    return GroupRead.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<GroupRead> get(String groupId) async {
    final dio = _ref.read(apiClientProvider).dio;
    final resp = await dio.get('/groups/$groupId');
    return GroupRead.fromJson(resp.data as Map<String, dynamic>);
  }
}

final groupsRepositoryProvider = Provider<GroupsRepository>(GroupsRepository.new);

/// Discover public groups, optionally filtered by backend category. `null` = all.
final discoverGroupsProvider =
    FutureProvider.autoDispose.family<List<GroupSummary>, String?>((ref, category) {
  return ref.watch(groupsRepositoryProvider).discover(category: category);
});

final myGroupsProvider = FutureProvider.autoDispose<List<GroupSummary>>((ref) {
  return ref.watch(groupsRepositoryProvider).myGroups();
});

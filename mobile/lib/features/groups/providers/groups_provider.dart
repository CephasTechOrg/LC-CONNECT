import 'package:dio/dio.dart';
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

  /// Groups the current user has a pending invite to (includes private/unlisted ones that
  /// never appear in discovery).
  Future<List<GroupSummary>> myInvites() async {
    final dio = _ref.read(apiClientProvider).dio;
    final resp = await dio.get('/groups/invites');
    return (resp.data as List)
        .map((j) => GroupSummary.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> acceptInvite(String groupId) =>
      _ref.read(apiClientProvider).dio.post('/groups/$groupId/invites/accept');

  Future<void> declineInvite(String groupId) =>
      _ref.read(apiClientProvider).dio.post('/groups/$groupId/invites/decline');

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

  // ── membership + admin ──────────────────────────────────────────────────────

  Future<List<GroupMember>> members(String groupId) async {
    final dio = _ref.read(apiClientProvider).dio;
    final resp = await dio.get('/groups/$groupId/members');
    return (resp.data as List)
        .map((j) => GroupMember.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<GroupMember>> requests(String groupId) async {
    final dio = _ref.read(apiClientProvider).dio;
    final resp = await dio.get('/groups/$groupId/requests');
    return (resp.data as List)
        .map((j) => GroupMember.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> approve(String groupId, String userId) =>
      _ref.read(apiClientProvider).dio.post('/groups/$groupId/requests/$userId/approve');

  Future<void> reject(String groupId, String userId) =>
      _ref.read(apiClientProvider).dio.post('/groups/$groupId/requests/$userId/reject');

  Future<void> invite(String groupId, String userId) => _ref
      .read(apiClientProvider)
      .dio
      .post('/groups/$groupId/invites', data: {'user_id': userId});

  Future<void> changeRole(String groupId, String userId, String role) => _ref
      .read(apiClientProvider)
      .dio
      .patch('/groups/$groupId/members/$userId', data: {'role': role});

  Future<void> transferOwnership(String groupId, String userId) => _ref
      .read(apiClientProvider)
      .dio
      .post('/groups/$groupId/transfer', data: {'user_id': userId});

  /// Remove (or, with [ban], ban) a member. Banned members cannot rejoin.
  Future<void> removeMember(String groupId, String userId, {bool ban = false}) =>
      _ref.read(apiClientProvider).dio.delete(
        '/groups/$groupId/members/$userId',
        queryParameters: ban ? {'ban': true} : null,
      );

  Future<void> leave(String groupId) =>
      _ref.read(apiClientProvider).dio.delete('/groups/$groupId/members/me');

  Future<void> delete(String groupId) =>
      _ref.read(apiClientProvider).dio.delete('/groups/$groupId');

  Future<GroupRead> update(String groupId, Map<String, dynamic> changes) async {
    final dio = _ref.read(apiClientProvider).dio;
    final resp = await dio.patch('/groups/$groupId', data: changes);
    return GroupRead.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<GroupRead> uploadAvatar(
    String groupId, {
    required String path,
    required String mimeType,
    required String filename,
  }) async {
    final dio = _ref.read(apiClientProvider).dio;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    final resp = await dio.post('/groups/$groupId/avatar', data: formData);
    return GroupRead.fromJson(resp.data as Map<String, dynamic>);
  }
}

final groupsRepositoryProvider = Provider<GroupsRepository>(GroupsRepository.new);

/// Args for discovery: an optional backend category and an optional name search. Records have
/// value equality, so identical (category, query) pairs share one cached request.
typedef DiscoverArgs = ({String? category, String? query});

/// Discover public groups, optionally filtered by category and/or a name search. `null` = all.
final discoverGroupsProvider =
    FutureProvider.autoDispose.family<List<GroupSummary>, DiscoverArgs>((ref, args) {
  return ref.watch(groupsRepositoryProvider).discover(category: args.category, query: args.query);
});

final myGroupsProvider = FutureProvider.autoDispose<List<GroupSummary>>((ref) {
  return ref.watch(groupsRepositoryProvider).myGroups();
});

/// Groups the current user has been invited to — drives the Pending invites section.
final myInvitesProvider = FutureProvider.autoDispose<List<GroupSummary>>((ref) {
  return ref.watch(groupsRepositoryProvider).myInvites();
});

/// Full group detail (name, description, my role, counts) — the header of the detail screen.
final groupDetailProvider =
    FutureProvider.autoDispose.family<GroupRead, String>((ref, groupId) {
  return ref.watch(groupsRepositoryProvider).get(groupId);
});

/// Active members of a group, for the members list.
final groupMembersProvider =
    FutureProvider.autoDispose.family<List<GroupMember>, String>((ref, groupId) {
  return ref.watch(groupsRepositoryProvider).members(groupId);
});

/// Pending join requests — admin-only; the endpoint 403s for non-admins.
final groupRequestsProvider =
    FutureProvider.autoDispose.family<List<GroupMember>, String>((ref, groupId) {
  return ref.watch(groupsRepositoryProvider).requests(groupId);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';

class PublishingCapabilities {
  final bool canPublish;
  final bool staffPublishingEnabled;
  final String? reason;

  const PublishingCapabilities({
    required this.canPublish,
    required this.staffPublishingEnabled,
    this.reason,
  });

  factory PublishingCapabilities.fromJson(Map<String, dynamic> json) =>
      PublishingCapabilities(
        canPublish: json['can_publish'] as bool? ?? false,
        staffPublishingEnabled: json['staff_publishing_enabled'] as bool? ?? false,
        reason: json['reason'] as String?,
      );
}

class AuthorCampusPost {
  final String id;
  final String kind;
  final String title;
  final String? summary;
  final String body;
  final String audience;
  final String? category;
  final String priority;
  final String status;
  final DateTime? publishAt;
  final DateTime? expiresAt;
  final String? externalUrl;

  const AuthorCampusPost({
    required this.id,
    required this.kind,
    required this.title,
    this.summary,
    required this.body,
    required this.audience,
    this.category,
    required this.priority,
    required this.status,
    this.publishAt,
    this.expiresAt,
    this.externalUrl,
  });

  factory AuthorCampusPost.fromJson(Map<String, dynamic> json) => AuthorCampusPost(
        id: json['id'] as String,
        kind: json['kind'] as String,
        title: json['title'] as String,
        summary: json['summary'] as String?,
        body: json['body'] as String,
        audience: json['audience'] as String,
        category: json['category'] as String?,
        priority: json['priority'] as String,
        status: json['status'] as String,
        publishAt: json['publish_at'] != null
            ? DateTime.parse(json['publish_at'] as String)
            : null,
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        externalUrl: json['external_url'] as String?,
      );

  bool get isDraft => status == 'draft';
  bool get isPublished => status == 'published';
}

final publishingCapabilitiesProvider = FutureProvider<PublishingCapabilities>((ref) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/campus-hub/publishing/capabilities');
  return PublishingCapabilities.fromJson(response.data as Map<String, dynamic>);
});

final myCampusPostsProvider = FutureProvider<List<AuthorCampusPost>>((ref) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/campus-hub/my-posts');
  return (response.data as List)
      .map((json) => AuthorCampusPost.fromJson(json as Map<String, dynamic>))
      .toList();
});

class CampusPublishingService {
  final ApiClient _client;
  CampusPublishingService(this._client);

  Future<AuthorCampusPost> createPost({
    required String kind,
    required String title,
    required String body,
    String? summary,
    String audience = 'all',
    String priority = 'normal',
  }) async {
    final response = await _client.dio.post('/campus-hub/my-posts', data: {
      'kind': kind,
      'title': title,
      'body': body,
      if (summary != null && summary.isNotEmpty) 'summary': summary,
      'audience': audience,
      'priority': priority,
    });
    return AuthorCampusPost.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AuthorCampusPost> publishPost(String postId) async {
    final response = await _client.dio.post('/campus-hub/my-posts/$postId/publish');
    return AuthorCampusPost.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AuthorCampusPost> archivePost(String postId) async {
    final response = await _client.dio.post('/campus-hub/my-posts/$postId/archive');
    return AuthorCampusPost.fromJson(response.data as Map<String, dynamic>);
  }
}

final campusPublishingServiceProvider = Provider<CampusPublishingService>(
  (ref) => CampusPublishingService(ref.watch(apiClientProvider)),
);

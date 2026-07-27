import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/campus_post.dart';

class CampusPostsQuery {
  final String? kind;
  final String? priority;
  final String? category;

  const CampusPostsQuery({this.kind, this.priority, this.category});

  @override
  bool operator ==(Object other) =>
      other is CampusPostsQuery &&
      other.kind == kind &&
      other.priority == priority &&
      other.category == category;

  @override
  int get hashCode => Object.hash(kind, priority, category);
}

final campusHubOverviewProvider = FutureProvider<CampusHubOverview>((ref) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/campus-hub/overview');
  return CampusHubOverview.fromJson(response.data as Map<String, dynamic>);
});

final campusPostsProvider =
    FutureProvider.family<List<CampusPostSummary>, CampusPostsQuery>((ref, query) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get(
    '/campus-hub/posts',
    queryParameters: {
      if (query.kind != null) 'kind': query.kind,
      if (query.priority != null) 'priority': query.priority,
      if (query.category != null) 'category': query.category,
    },
  );
  return (response.data as List)
      .map((json) => CampusPostSummary.fromJson(json as Map<String, dynamic>))
      .toList();
});

final campusPostProvider = FutureProvider.family<CampusPost, String>((ref, postId) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/campus-hub/posts/$postId');
  return CampusPost.fromJson(response.data as Map<String, dynamic>);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/campus_resource.dart';

class ResourcesQuery {
  final String? category;

  const ResourcesQuery({this.category});

  @override
  bool operator ==(Object other) => other is ResourcesQuery && other.category == category;

  @override
  int get hashCode => category.hashCode;
}

final campusResourcesProvider =
    FutureProvider.family<List<CampusResource>, ResourcesQuery>((ref, query) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get(
    '/campus-hub/resources',
    queryParameters: {
      if (query.category != null && query.category!.isNotEmpty && query.category != 'all')
        'category': query.category,
    },
  );
  return (response.data as List)
      .map((json) => CampusResource.fromJson(json as Map<String, dynamic>))
      .toList();
});

final campusResourceProvider =
    FutureProvider.family<CampusResource, String>((ref, resourceId) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/campus-hub/resources/$resourceId');
  return CampusResource.fromJson(response.data as Map<String, dynamic>);
});

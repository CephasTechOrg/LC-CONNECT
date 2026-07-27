import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';

class DirectoryEntry {
  final String positionId;
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String category;
  final String officialTitle;
  final String department;
  final String? officeLocation;
  final String? phone;
  final String contactEmail;
  final String? availability;
  final String? bio;

  const DirectoryEntry({
    required this.positionId,
    required this.userId,
    this.displayName,
    this.avatarUrl,
    required this.category,
    required this.officialTitle,
    required this.department,
    this.officeLocation,
    this.phone,
    required this.contactEmail,
    this.availability,
    this.bio,
  });

  factory DirectoryEntry.fromJson(Map<String, dynamic> json) => DirectoryEntry(
        positionId: json['position_id'] as String,
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        category: json['category'] as String,
        officialTitle: json['official_title'] as String,
        department: json['department'] as String,
        officeLocation: json['office_location'] as String?,
        phone: json['phone'] as String?,
        contactEmail: json['contact_email'] as String,
        availability: json['availability'] as String?,
        bio: json['bio'] as String?,
      );
}

const directoryCategories = <String, String>{
  'all': 'All',
  'academic': 'Academic',
  'advising': 'Advising',
  'residential_life': 'Residential Life',
  'campus_services': 'Campus Services',
};

class DirectoryQuery {
  final String? category;
  final String? query;

  const DirectoryQuery({this.category, this.query});

  @override
  bool operator ==(Object other) =>
      other is DirectoryQuery && other.category == category && other.query == query;

  @override
  int get hashCode => Object.hash(category, query);
}

final campusDirectoryProvider =
    FutureProvider.family<List<DirectoryEntry>, DirectoryQuery>((ref, query) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get(
    '/campus-hub/directory',
    queryParameters: {
      if (query.category != null && query.category!.isNotEmpty && query.category != 'all')
        'category': query.category,
      if (query.query != null && query.query!.isNotEmpty) 'query': query.query,
    },
  );
  return (response.data as List)
      .map((json) => DirectoryEntry.fromJson(json as Map<String, dynamic>))
      .toList();
});

final campusDirectoryEntryProvider =
    FutureProvider.family<DirectoryEntry, String>((ref, positionId) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/campus-hub/directory/$positionId');
  return DirectoryEntry.fromJson(response.data as Map<String, dynamic>);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// A student as a staff member sees them in the student directory — recognise + reach out.
class StudentEntry {
  final String profileId;
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String? major;
  final int? classYear;

  const StudentEntry({
    required this.profileId,
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.major,
    this.classYear,
  });

  factory StudentEntry.fromJson(Map<String, dynamic> j) => StudentEntry(
        profileId: j['profile_id'] as String,
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        major: j['major'] as String?,
        classYear: j['class_year'] as int?,
      );

  String get name => displayName ?? 'LC Student';
}

/// The staff-only student directory. `query` (trimmed) searches name/major; empty lists everyone.
final studentDirectoryProvider =
    FutureProvider.autoDispose.family<List<StudentEntry>, String>((ref, query) async {
  final params = <String, dynamic>{'limit': 50};
  if (query.trim().isNotEmpty) params['query'] = query.trim();
  final resp = await ref.read(apiClientProvider).dio.get('/campus-hub/students', queryParameters: params);
  return (resp.data as List).map((j) => StudentEntry.fromJson(j as Map<String, dynamic>)).toList();
});

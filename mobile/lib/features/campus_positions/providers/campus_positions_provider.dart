import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';

class CampusPosition {
  final String id;
  final String category;
  final String officialTitle;
  final String department;
  final String? officeLocation;
  final String? phone;
  final String contactEmail;
  final String? availability;
  final String? bio;
  final String status;

  const CampusPosition({
    required this.id,
    required this.category,
    required this.officialTitle,
    required this.department,
    this.officeLocation,
    this.phone,
    required this.contactEmail,
    this.availability,
    this.bio,
    required this.status,
  });

  factory CampusPosition.fromJson(Map<String, dynamic> json) => CampusPosition(
        id: json['id'] as String,
        category: json['category'] as String,
        officialTitle: json['official_title'] as String,
        department: json['department'] as String,
        officeLocation: json['office_location'] as String?,
        phone: json['phone'] as String?,
        contactEmail: json['contact_email'] as String,
        availability: json['availability'] as String?,
        bio: json['bio'] as String?,
        status: json['status'] as String,
      );

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';
  bool get canResubmit => status == 'rejected' || status == 'revoked';
}

abstract class CampusPositionsService {
  Future<CampusPosition?> getMyPosition();

  Future<void> submitPosition({
    required String category,
    required String officialTitle,
    required String department,
    String? officeLocation,
    String? phone,
    String? availability,
    String? bio,
  });
}

class _ApiCampusPositionsService implements CampusPositionsService {
  final ApiClient _client;
  _ApiCampusPositionsService(this._client);

  @override
  Future<CampusPosition?> getMyPosition() async {
    try {
      final response = await _client.dio.get('/campus-positions/me');
      final data = response.data;
      if (data == null) return null;
      return CampusPosition.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> submitPosition({
    required String category,
    required String officialTitle,
    required String department,
    String? officeLocation,
    String? phone,
    String? availability,
    String? bio,
  }) async {
    await _client.dio.post('/campus-positions/me', data: {
      'category': category,
      'official_title': officialTitle,
      'department': department,
      if (officeLocation != null && officeLocation.isNotEmpty)
        'office_location': officeLocation,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (availability != null && availability.isNotEmpty) 'availability': availability,
      if (bio != null && bio.isNotEmpty) 'bio': bio,
    });
  }
}

final campusPositionsServiceProvider = Provider<CampusPositionsService>(
  (ref) => _ApiCampusPositionsService(ref.watch(apiClientProvider)),
);

final myCampusPositionProvider = FutureProvider<CampusPosition?>((ref) async {
  ref.watch(authNotifierProvider);
  return ref.watch(campusPositionsServiceProvider).getMyPosition();
});

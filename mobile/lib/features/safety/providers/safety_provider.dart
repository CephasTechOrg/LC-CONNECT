import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';

abstract class SafetyService {
  Future<void> blockUser(String userId);
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? details,
  });
}

class _ApiSafetyService extends SafetyService {
  final ApiClient _client;
  _ApiSafetyService(this._client);

  @override
  Future<void> blockUser(String userId) async {
    await _client.dio.post('/blocks/$userId');
  }

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? details,
  }) async {
    await _client.dio.post('/reports', data: {
      'reported_user_id': userId,
      'reason': reason,
      if (details != null && details.isNotEmpty) 'details': details,
    });
  }
}

final safetyServiceProvider = Provider<SafetyService>(
  (ref) => _ApiSafetyService(ref.watch(apiClientProvider)),
);

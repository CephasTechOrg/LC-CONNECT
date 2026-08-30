import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

class SuspensionStatus {
  final String supportEmail;
  final OpenAppeal? openAppeal;

  const SuspensionStatus({required this.supportEmail, this.openAppeal});

  factory SuspensionStatus.fromJson(Map<String, dynamic> json) => SuspensionStatus(
        supportEmail: json['support_email'] as String? ?? 'support@livingstone.edu',
        openAppeal: json['open_appeal'] != null
            ? OpenAppeal.fromJson(json['open_appeal'] as Map<String, dynamic>)
            : null,
      );
}

class OpenAppeal {
  final String id;
  final String status;
  final String message;
  final String? adminNote;
  final DateTime createdAt;

  const OpenAppeal({
    required this.id,
    required this.status,
    required this.message,
    this.adminNote,
    required this.createdAt,
  });

  factory OpenAppeal.fromJson(Map<String, dynamic> json) => OpenAppeal(
        id: json['id'].toString(),
        status: json['status'] as String,
        message: json['message'] as String,
        adminNote: json['admin_note'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

final suspensionStatusProvider = FutureProvider.autoDispose<SuspensionStatus>((ref) async {
  final client = ref.read(apiClientProvider);
  final response = await client.dio.get('/account/suspension-status');
  return SuspensionStatus.fromJson(response.data as Map<String, dynamic>);
});

Future<void> submitSuspensionAppeal(WidgetRef ref, String message) async {
  final client = ref.read(apiClientProvider);
  await client.dio.post(
    '/account/suspension-appeal',
    data: {'message': message},
  );
  ref.invalidate(suspensionStatusProvider);
}

bool isAccountSuspendedError(DioException error) {
  if (error.response?.statusCode != 403) return false;
  final data = error.response?.data;
  if (data is Map && data['detail'] == 'account_suspended') return true;
  return data == 'account_suspended';
}

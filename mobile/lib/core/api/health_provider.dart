import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'api_client.dart';

enum BackendStatus { checking, online, offline }

final backendStatusProvider = FutureProvider<BackendStatus>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    // Hit /health (not under /api/v1)
    final baseUrl = client.dio.options.baseUrl.replaceAll('/api/v1', '');
    await Dio().get(
      '$baseUrl/health',
      options: Options(sendTimeout: const Duration(seconds: 5)),
    );
    return BackendStatus.online;
  } catch (_) {
    return BackendStatus.offline;
  }
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

abstract class AccountService {
  Future<void> deleteAccount({
    required String confirmEmail,
    required String password,
  });

  /// Machine-readable JSON map of the caller's own data (`GET /account/export`).
  Future<Map<String, dynamic>> exportAccount();
}

class _ApiAccountService implements AccountService {
  final ApiClient _client;

  _ApiAccountService(this._client);

  @override
  Future<void> deleteAccount({
    required String confirmEmail,
    required String password,
  }) async {
    await _client.dio.delete(
      '/account',
      data: {
        'confirm_email': confirmEmail.trim().toLowerCase(),
        'password': password,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> exportAccount() async {
    final response = await _client.dio.get<Map<String, dynamic>>('/account/export');
    return Map<String, dynamic>.from(response.data ?? const {});
  }
}

final accountServiceProvider = Provider<AccountService>(
  (ref) => _ApiAccountService(ref.watch(apiClientProvider)),
);

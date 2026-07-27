import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

abstract class AccountService {
  Future<void> deleteAccount({required String confirmEmail});
}

class _ApiAccountService implements AccountService {
  final ApiClient _client;

  _ApiAccountService(this._client);

  @override
  Future<void> deleteAccount({required String confirmEmail}) async {
    await _client.dio.delete(
      '/account',
      data: {'confirm_email': confirmEmail.trim().toLowerCase()},
    );
  }
}

final accountServiceProvider = Provider<AccountService>(
  (ref) => _ApiAccountService(ref.watch(apiClientProvider)),
);

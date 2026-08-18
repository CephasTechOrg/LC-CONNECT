import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase auth session in the platform keystore instead of SharedPreferences.
///
/// `Supabase.initialize` defaults `localStorage` to `SharedPreferencesLocalStorage`, which writes
/// the persisted session — **including the refresh token** — as plaintext: app-private XML on
/// Android, a plist in the app container on iOS. Both are readable on a rooted/jailbroken device
/// and can surface in an unencrypted device backup.
///
/// The refresh token is the credential worth protecting: it mints new access tokens indefinitely
/// until revoked, long outliving the ~1h access token. So it belongs behind the Keychain /
/// EncryptedSharedPreferences that `flutter_secure_storage` wraps.
///
/// Changing where sessions live means the old SharedPreferences entry is not found on first run
/// after the update, so everyone signs in once more. That is deliberate: a migration would have
/// to read the plaintext token to move it, and would carry that code forever to save a single
/// sign-in.
/// Android encryption is the package default in v10 (the old `encryptedSharedPreferences` flag is
/// deprecated and ignored). `first_unlock_this_device` is the iOS choice worth stating: the
/// session stays readable in the background after the first unlock — so token refresh and push
/// handling still work — but never leaves this device via an iCloud Keychain sync or backup.
const _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

class SecureSessionLocalStorage extends LocalStorage {
  const SecureSessionLocalStorage({required this.persistSessionKey});

  /// Matches the key Supabase would have used, so the two are never live at once.
  final String persistSessionKey;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _secureStorage.containsKey(key: persistSessionKey);

  /// Despite the name this returns the whole persisted session blob, not just the access
  /// token — that is the contract `SupabaseAuth` recovers a session from.
  @override
  Future<String?> accessToken() => _secureStorage.read(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secureStorage.write(key: persistSessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _secureStorage.delete(key: persistSessionKey);
}

/// The PKCE code verifier, held to the same standard as the session above.
///
/// Shorter-lived — it only spans a single auth exchange — but it is still the secret half of
/// that exchange, and there is no reason to leave it in plaintext once the keystore is wired up.
class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage();

  @override
  Future<String?> getItem({required String key}) => _secureStorage.read(key: key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _secureStorage.write(key: key, value: value);

  @override
  Future<void> removeItem({required String key}) => _secureStorage.delete(key: key);
}

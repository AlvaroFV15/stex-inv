import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_store.dart';

/// Guarda la sesión de Supabase (access + refresh token) en Keystore/Keychain
/// en lugar de SharedPreferences, como pide la especificación v2.
class SecureAuthStorage extends LocalStorage {
  const SecureAuthStorage();

  static const _clave = 'stex_supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      (await SecureStore.storage.read(key: _clave)) != null;

  @override
  Future<String?> accessToken() => SecureStore.storage.read(key: _clave);

  @override
  Future<void> persistSession(String persistSessionString) =>
      SecureStore.storage.write(key: _clave, value: persistSessionString);

  @override
  Future<void> removePersistedSession() =>
      SecureStore.storage.delete(key: _clave);
}

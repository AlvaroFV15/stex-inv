import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Datos sensibles del dispositivo: clave de la base y cuenta vinculada.
abstract class AlmacenSeguro {
  /// Clave AES-256 de la base local. Se genera una sola vez por instalación.
  Future<String> claveBaseDatos();
  Future<String?> emailVinculado();
  Future<void> guardarEmailVinculado(String email);

  /// Borra todo (desvincular). La próxima vinculación genera otra clave.
  Future<void> borrarTodo();
}

/// Implementación con Android Keystore / iOS Keychain.
class SecureStore implements AlmacenSeguro {
  const SecureStore();

  static const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const _claveDb = 'stex_db_key';
  static const _emailVinculado = 'stex_email_vinculado';

  /// 32 bytes aleatorios en hexadecimal (64 caracteres).
  static String generarClave([Random? rnd]) {
    final r = rnd ?? Random.secure();
    return List<int>.generate(32, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  Future<String> claveBaseDatos() async {
    final existente = await storage.read(key: _claveDb);
    if (existente != null && existente.isNotEmpty) return existente;
    final clave = generarClave();
    await storage.write(key: _claveDb, value: clave);
    return clave;
  }

  @override
  Future<String?> emailVinculado() => storage.read(key: _emailVinculado);

  @override
  Future<void> guardarEmailVinculado(String email) =>
      storage.write(key: _emailVinculado, value: email);

  @override
  Future<void> borrarTodo() => storage.deleteAll();
}

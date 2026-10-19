import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';

/// No se pudo renovar el token porque no hay red.
class SinConexionAuth implements Exception {
  const SinConexionAuth();
}

/// Sesión del dispositivo (la cuenta del almacén).
abstract class ServicioAuth {
  /// Lanza [ApiException] con un mensaje en español si falla.
  Future<void> iniciarSesion(String email, String password);

  /// Token vigente para la API; lo renueva si expiró o si se fuerza.
  /// Devuelve null si no hay sesión o ya no se puede renovar.
  /// Lanza [SinConexionAuth] si la renovación falló por red.
  Future<String?> tokenVigente({bool forzarRenovacion = false});

  Future<void> cerrarSesion();
}

/// Implementación con Supabase Auth. Se inicia sesión una sola vez;
/// el token se renueva cuando hay red.
class SupabaseAuthService implements ServicioAuth {
  SupabaseAuthService([GoTrueClient? cliente]) : _cliente = cliente;

  final GoTrueClient? _cliente;
  GoTrueClient get _auth => _cliente ?? Supabase.instance.client.auth;

  @override
  Future<void> iniciarSesion(String email, String password) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthRetryableFetchException {
      throw ApiException('No se pudo conectar con el servidor.', sinConexion: true);
    } on AuthException catch (e) {
      throw ApiException(traducirErrorAuth(e.message));
    }
  }

  @override
  Future<String?> tokenVigente({bool forzarRenovacion = false}) async {
    var sesion = _auth.currentSession;
    if (sesion == null) return null;
    if (forzarRenovacion || sesion.isExpired) {
      try {
        sesion = (await _auth.refreshSession()).session;
      } on AuthRetryableFetchException {
        throw const SinConexionAuth();
      } on AuthException {
        return null;
      }
    }
    return sesion?.accessToken;
  }

  @override
  Future<void> cerrarSesion() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Sin red el cierre remoto falla, pero la sesión local igual se borra.
    }
  }
}

/// Traduce los mensajes en inglés de Supabase Auth.
String traducirErrorAuth(String mensaje) {
  final m = mensaje.toLowerCase();
  if (m.contains('invalid login') || m.contains('invalid credentials')) {
    return 'Correo o contraseña incorrectos.';
  }
  if (m.contains('email not confirmed')) return 'La cuenta no está confirmada.';
  if (m.contains('network') || m.contains('socket') || m.contains('failed host')) {
    return 'No se pudo conectar con el servidor.';
  }
  return mensaje;
}

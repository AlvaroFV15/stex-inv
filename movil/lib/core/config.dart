/// Configuración inyectada al compilar con
/// `flutter run --dart-define-from-file=dart_defines.json`.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// URL del panel Next.js, sin barra final. Ej: https://stex.apjltextil.com
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Por encima de este peso (kg) se pide confirmación antes de guardar.
  static const pesoAlertaKg = 150.0;

  /// Los libros ya enviados se borran del dispositivo después de estos días.
  static const diasRetencionEnviados = 7;

  /// Intentos de PIN fallidos antes de bloquear temporalmente al operario.
  static const maxIntentosPin = 5;
  static const bloqueoPin = Duration(seconds: 60);

  static bool get completa =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      apiBaseUrl.isNotEmpty;
}

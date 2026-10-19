import 'package:dio/dio.dart';

import 'auth_service.dart';

/// Error de la API ya traducido a algo que la app sabe manejar.
class ApiException implements Exception {
  ApiException(
    this.mensaje, {
    this.sinConexion = false,
    this.sesionInvalida = false,
    this.status,
  });

  final String mensaje;

  /// No se llegó al servidor (sin red, timeout, 5xx). Se reintenta solo.
  final bool sinConexion;

  /// La sesión del dispositivo ya no sirve; hay que volver a autenticar.
  final bool sesionInvalida;
  final int? status;

  @override
  String toString() => mensaje;
}

class ResultadoSubida {
  const ResultadoSubida({required this.libroId, required this.duplicado});
  final String libroId;

  /// El servidor ya tenía este libro (reenvío tras un corte de red).
  final bool duplicado;
}

/// Contrato de /api/sync que usa la app.
abstract class SyncApi {
  /// GET /api/sync/download. Devuelve el JSON completo ({success, data, timestamp}).
  Future<Map<String, dynamic>> descargarMaestros();

  /// POST /api/sync/upload.
  Future<ResultadoSubida> subirLibro(Map<String, Object?> cuerpo);
}

const _mensajeSesion =
    'La sesión del dispositivo expiró. Vuelve a ingresar la contraseña del almacén.';

/// Cliente HTTP de la API de sincronización del panel.
class ApiClient implements SyncApi {
  ApiClient(this._auth, {required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            )) {
    _dio.options.baseUrl = baseUrl;
  }

  final ServicioAuth _auth;
  final Dio _dio;

  @override
  Future<Map<String, dynamic>> descargarMaestros() async {
    final r = await _conToken((token) =>
        _dio.get<Map<String, dynamic>>('/api/sync/download', options: _opciones(token)));
    final cuerpo = r.data ?? const {};
    if (cuerpo['success'] != true || cuerpo['data'] is! Map) {
      throw ApiException(_mensaje(cuerpo) ?? 'Respuesta inesperada del servidor.');
    }
    return cuerpo;
  }

  @override
  Future<ResultadoSubida> subirLibro(Map<String, Object?> cuerpo) async {
    final r = await _conToken((token) => _dio.post<Map<String, dynamic>>(
          '/api/sync/upload',
          data: cuerpo,
          options: _opciones(token),
        ));
    final datos = r.data ?? const {};
    if (datos['success'] != true) {
      throw ApiException(_mensaje(datos) ?? 'El servidor no confirmó el envío.');
    }
    return ResultadoSubida(
      libroId: (datos['libro_id'] ?? cuerpo['libro_id']).toString(),
      duplicado: datos['duplicado'] == true,
    );
  }

  Options _opciones(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  /// Ejecuta la petición con el token vigente. Si el servidor responde 401,
  /// fuerza una renovación del token y reintenta una vez.
  Future<Response<T>> _conToken<T>(
      Future<Response<T>> Function(String token) peticion) async {
    try {
      final token = await _auth.tokenVigente();
      if (token == null) throw ApiException(_mensajeSesion, sesionInvalida: true);
      try {
        return await peticion(token);
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) throw _traducir(e);
        final nuevo = await _auth.tokenVigente(forzarRenovacion: true);
        if (nuevo == null) {
          throw ApiException(_mensajeSesion, sesionInvalida: true, status: 401);
        }
        try {
          return await peticion(nuevo);
        } on DioException catch (e2) {
          throw _traducir(e2);
        }
      }
    } on SinConexionAuth {
      throw ApiException('No se pudo conectar con el servidor.', sinConexion: true);
    }
  }

  ApiException _traducir(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return ApiException('No se pudo conectar con el servidor.', sinConexion: true);
      default:
        break;
    }
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final mensaje = data is Map ? _mensaje(data) : null;
    if (status == 401) {
      return ApiException(mensaje ?? _mensajeSesion, sesionInvalida: true, status: 401);
    }
    if (status != null && status >= 500) {
      return ApiException(mensaje ?? 'Error del servidor ($status). Se reintentará.',
          sinConexion: true, status: status);
    }
    if (status == null) {
      return ApiException('No se pudo conectar con el servidor.', sinConexion: true);
    }
    return ApiException(mensaje ?? 'Error $status al comunicarse con el servidor.',
        status: status);
  }

  String? _mensaje(Map<dynamic, dynamic> m) => (m['message'] ?? m['error'])?.toString();
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stex_inv_movil/data/remote/api_client.dart';

import '../helpers/fakes.dart';

/// Adaptador HTTP falso: responde en orden lo que se le encola.
class AdaptadorFalso implements HttpClientAdapter {
  final List<RequestOptions> peticiones = [];
  final List<Object> respuestas = [];

  void responder(int status, Object body) => respuestas.add(
        ResponseBody.fromString(jsonEncode(body), status, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        }),
      );

  void fallarConexion() => respuestas.add('sin-red');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    peticiones.add(options);
    final r = respuestas.removeAt(0);
    if (r == 'sin-red') {
      throw DioException.connectionError(requestOptions: options, reason: 'sin red');
    }
    return r as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AuthFalso auth;
  late AdaptadorFalso http;
  late ApiClient api;

  setUp(() async {
    auth = AuthFalso();
    await auth.iniciarSesion(correo, password);
    http = AdaptadorFalso();
    api = ApiClient(auth, baseUrl: 'https://panel.test', dio: Dio()..httpClientAdapter = http);
  });

  String? tokenEnviado(int i) => http.peticiones[i].headers['Authorization'] as String?;

  final cuerpo = <String, Object?>{'libro_id': 'l1', 'detalles': []};

  group('descargarMaestros', () {
    test('usa la URL base y el token Bearer', () async {
      http.responder(200, maestrosDeEjemplo());
      final r = await api.descargarMaestros();
      expect(r['success'], isTrue);
      expect(http.peticiones.single.uri.toString(), 'https://panel.test/api/sync/download');
      expect(tokenEnviado(0), 'Bearer token-1');
    });

    test('success:false en un 200 se reporta como error', () async {
      http.responder(200, {'success': false, 'message': 'algo raro'});
      await expectLater(
        api.descargarMaestros(),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'algo raro')),
      );
    });
  });

  group('subirLibro', () {
    test('envía el cuerpo y lee duplicado', () async {
      http.responder(200, {'success': true, 'libro_id': 'l1', 'duplicado': true});
      final r = await api.subirLibro(cuerpo);
      expect(r.libroId, 'l1');
      expect(r.duplicado, isTrue);
      final p = http.peticiones.single;
      expect(p.method, 'POST');
      expect(p.path, '/api/sync/upload');
      expect(p.data, cuerpo);
    });

    test('duplicado ausente se toma como false', () async {
      http.responder(200, {'success': true, 'libro_id': 'l1'});
      expect((await api.subirLibro(cuerpo)).duplicado, isFalse);
    });
  });

  group('sesión', () {
    test('sin sesión no hace la petición', () async {
      auth.token = null;
      await expectLater(
        api.descargarMaestros(),
        throwsA(isA<ApiException>().having((e) => e.sesionInvalida, 'sesionInvalida', isTrue)),
      );
      expect(http.peticiones, isEmpty);
    });

    test('ante un 401 renueva el token y reintenta una vez', () async {
      http
        ..responder(401, {'success': false, 'message': 'Sesión no válida o expirada.'})
        ..responder(200, {'success': true, 'libro_id': 'l1', 'duplicado': false});
      final r = await api.subirLibro(cuerpo);
      expect(r.libroId, 'l1');
      expect(auth.renovaciones, 1);
      expect(tokenEnviado(0), 'Bearer token-1');
      expect(tokenEnviado(1), 'Bearer token-2');
    });

    test('401 y la renovación también es rechazada → sesión inválida', () async {
      auth.renovacionInvalida = true;
      http.responder(401, {'success': false});
      await expectLater(
        api.subirLibro(cuerpo),
        throwsA(isA<ApiException>()
            .having((e) => e.sesionInvalida, 'sesionInvalida', isTrue)
            .having((e) => e.status, 'status', 401)),
      );
      expect(http.peticiones, hasLength(1));
    });

    test('401 dos veces seguidas → sesión inválida', () async {
      http
        ..responder(401, {'success': false})
        ..responder(401, {'success': false, 'message': 'Sesión no válida o expirada.'});
      await expectLater(
        api.subirLibro(cuerpo),
        throwsA(isA<ApiException>().having((e) => e.sesionInvalida, 'sesionInvalida', isTrue)),
      );
    });

    test('si la renovación falla por red, se trata como sin conexión', () async {
      auth.renovacionSinRed = true;
      http.responder(401, {'success': false});
      await expectLater(
        api.subirLibro(cuerpo),
        throwsA(isA<ApiException>()
            .having((e) => e.sinConexion, 'sinConexion', isTrue)
            .having((e) => e.sesionInvalida, 'sesionInvalida', isFalse)),
      );
    });
  });

  group('errores', () {
    test('sin red → sinConexion', () async {
      http.fallarConexion();
      await expectLater(
        api.descargarMaestros(),
        throwsA(isA<ApiException>().having((e) => e.sinConexion, 'sinConexion', isTrue)),
      );
    });

    test('5xx → sinConexion (se reintenta) con el mensaje del servidor', () async {
      http.responder(500, {'success': false, 'message': 'No se pudo guardar el libro.'});
      await expectLater(
        api.subirLibro(cuerpo),
        throwsA(isA<ApiException>()
            .having((e) => e.sinConexion, 'sinConexion', isTrue)
            .having((e) => e.status, 'status', 500)
            .having((e) => e.mensaje, 'mensaje', 'No se pudo guardar el libro.')),
      );
    });

    for (final (status, mensaje) in [
      (400, 'El libro debe tener al menos un detalle.'),
      (403, 'La cuenta no puede registrar libros de otro almacén.'),
      (422, 'Actualiza los datos maestros en la tablet.'),
    ]) {
      test('$status → error de negocio con el mensaje del servidor, sin reintento', () async {
        http.responder(status, {'success': false, 'message': mensaje});
        await expectLater(
          api.subirLibro(cuerpo),
          throwsA(isA<ApiException>()
              .having((e) => e.status, 'status', status)
              .having((e) => e.mensaje, 'mensaje', mensaje)
              .having((e) => e.sinConexion, 'sinConexion', isFalse)
              .having((e) => e.sesionInvalida, 'sesionInvalida', isFalse)),
        );
        expect(http.peticiones, hasLength(1));
      });
    }
  });
}

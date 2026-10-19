@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stex_inv_movil/core/pin_hash.dart';
import 'package:stex_inv_movil/data/remote/api_client.dart';
import 'package:stex_inv_movil/data/remote/auth_service.dart';
import 'package:stex_inv_movil/data/repositories/libros_repository.dart';
import 'package:stex_inv_movil/data/repositories/maestros_repository.dart';
import 'package:stex_inv_movil/domain/models.dart';
import 'package:stex_inv_movil/state/sync_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../helpers/fakes.dart';

/// Pruebas de integración contra el servidor local (Docker):
/// cliente real de Supabase Auth + ApiClient real + base SQLite real.
///
///   docker compose up -d db api
///   STEX_API_URL=http://localhost:8080 flutter test --tags integration
///
/// En Docker lo corre el servicio `movil-integracion`.

const _anonKey = 'local-anon-key';

void main() {
  final url = Platform.environment['STEX_API_URL'] ?? '';
  if (url.isEmpty) {
    test('servidor local no configurado', () {}, skip: 'Define STEX_API_URL para correr estas pruebas.');
    return;
  }

  late SupabaseClient supabase;
  late SupabaseAuthService auth;
  late ApiClient api;

  setUp(() {
    supabase = SupabaseClient(
      url,
      _anonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
    );
    auth = SupabaseAuthService(supabase.auth);
    api = ApiClient(auth, baseUrl: url);
  });

  tearDown(() => supabase.dispose());

  group('Auth (cliente real de Supabase contra el servidor local)', () {
    test('contraseña incorrecta → mensaje en español', () async {
      await expectLater(
        auth.iniciarSesion(correo, 'mala'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'Correo o contraseña incorrectos.')),
      );
      expect(await auth.tokenVigente(), isNull);
    });

    test('login y renovación del token', () async {
      await auth.iniciarSesion(correo, password);
      final t1 = await auth.tokenVigente();
      final t2 = await auth.tokenVigente(forzarRenovacion: true);
      expect(t1, isNotNull);
      expect(t2, isNotNull);
      expect(t2, isNot(t1));
      // El token renovado sirve para la API.
      expect((await api.descargarMaestros())['success'], isTrue);
    });

    test('cerrar sesión deja al cliente sin token', () async {
      await auth.iniciarSesion(correo, password);
      await auth.cerrarSesion();
      expect(await auth.tokenVigente(), isNull);
    });
  });

  group('/api/sync con la cuenta del almacén 1', () {
    setUp(() => auth.iniciarSesion(correo, password));

    test('download: solo su almacén y operarios con pin_hash correcto', () async {
      final r = await api.descargarMaestros();
      final data = r['data'] as Map<String, dynamic>;
      final almacenes = (data['almacenes'] as List).cast<Map<String, dynamic>>();
      final operarios = (data['operarios'] as List).cast<Map<String, dynamic>>();
      expect(almacenes.map((a) => a['almacen_id']), [idAlmacen1]);
      expect(operarios.map((o) => o['operario_id']).toSet(), {idJuan, idMaria});
      final juan = operarios.firstWhere((o) => o['operario_id'] == idJuan);
      expect(juan['pin_hash'], hashPin(idJuan, '1234'));
      expect(juan.containsKey('pin_seguridad'), isFalse);
    });

    test('flujo completo: descargar → capturar → cerrar → enviar → reenvío idempotente', () async {
      final base = await abrirBaseEnMemoria();
      addTearDown(base.cerrar);
      final maestros = MaestrosRepository(base.db);
      final libros = LibrosRepository(base.db);
      final sync = SyncController(
        libros: libros,
        maestros: maestros,
        api: api,
        conectividad: ConectividadFalsa(true),
        intervalo: const Duration(hours: 1),
      );
      addTearDown(sync.dispose);

      await sync.descargarMaestros();
      final almacen = (await maestros.almacenes()).single;
      final campana = (await maestros.campanas()).first;
      final juan = (await maestros.operarios()).firstWhere((o) => o.id == idJuan);
      final mats = await maestros.buscarMateriales('');

      final libro = await libros.crear(campana: campana, almacen: almacen, operario: juan);
      for (var i = 0; i < 2; i++) {
        final m = mats[i];
        await libros.agregarMovimiento(
          libroId: libro.id,
          material: m,
          cantidad: 10 + i,
          peso: 25.5 + i,
          observacion: i == 0 ? 'integración' : null,
          operarioId: juan.id,
        );
      }
      await libros.cerrar(libro.id);

      final r = await sync.enviarPendientes();
      expect(r.enviados, 1, reason: sync.ultimoMensaje);
      expect(r.duplicados, 0);
      expect((await libros.porId(libro.id))!.estado, EstadoLibro.enviado);

      // Reenvío del mismo libro (como si la respuesta se hubiera perdido).
      final cuerpo = SyncController.cuerpoDeEnvio(libro, await libros.movimientos(libro.id));
      final reenvio = await api.subirLibro(cuerpo);
      expect(reenvio.duplicado, isTrue);
      expect(reenvio.libroId, libro.id);
    });

    Map<String, Object?> cuerpo({String almacenId = idAlmacen1, String materialId = idHilo}) => {
          'libro_id': const Uuid().v4(),
          'campana_id': idCampana,
          'almacen_id': almacenId,
          'operario_id': idJuan,
          'fecha_conteo': DateTime.now().toUtc().toIso8601String(),
          'detalles': [
            {'material_id': materialId, 'cantidad_unidad': 1, 'peso_neto': 1.5, 'observacion': null},
          ],
        };

    test('libro de otro almacén → 403, sin reintento ni sesión inválida', () async {
      await expectLater(
        api.subirLibro(cuerpo(almacenId: idAlmacen2)),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.sinConexion, 'sinConexion', isFalse)
            .having((e) => e.sesionInvalida, 'sesionInvalida', isFalse)),
      );
    });

    test('material inexistente → 422 con indicación de actualizar maestros', () async {
      await expectLater(
        api.subirLibro(cuerpo(materialId: 'b1000000-0000-4000-8000-0000000000ff')),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 422)
            .having((e) => e.mensaje, 'mensaje', contains('Actualiza los datos maestros'))),
      );
    });

    test('servidor inalcanzable → sinConexion', () async {
      final caido = ApiClient(auth, baseUrl: 'http://127.0.0.1:9');
      await expectLater(
        caido.descargarMaestros(),
        throwsA(isA<ApiException>().having((e) => e.sinConexion, 'sinConexion', isTrue)),
      );
    });
  });
}

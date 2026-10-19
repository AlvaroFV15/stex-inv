import 'package:flutter_test/flutter_test.dart';
import 'package:stex_inv_movil/core/pin_hash.dart';
import 'package:stex_inv_movil/data/local/database.dart';
import 'package:stex_inv_movil/data/remote/api_client.dart';
import 'package:stex_inv_movil/data/repositories/libros_repository.dart';
import 'package:stex_inv_movil/data/repositories/maestros_repository.dart';
import 'package:stex_inv_movil/domain/models.dart';
import 'package:stex_inv_movil/state/sync_controller.dart';

import '../helpers/fakes.dart';

void main() {
  late AppDatabase base;
  late MaestrosRepository maestros;
  late LibrosRepository libros;
  late ConectividadFalsa red;
  late ApiFalsa api;
  late SyncController sync;

  setUp(() async {
    base = await abrirBaseEnMemoria();
    maestros = MaestrosRepository(base.db);
    libros = LibrosRepository(base.db);
    red = ConectividadFalsa(true);
    api = ApiFalsa();
    sync = SyncController(
      libros: libros,
      maestros: maestros,
      api: api,
      conectividad: red,
      intervalo: const Duration(hours: 1),
      retardoReconexion: Duration.zero,
    );
  });

  tearDown(() async {
    sync.dispose();
    await base.cerrar();
  });

  /// Crea un libro cerrado (pendiente de envío) con [n] registros.
  Future<Libro> libroCerrado({String almacenId = idAlmacen1, int n = 2}) async {
    final almacen = (await maestros.almacenes()).firstWhere((a) => a.id == almacenId);
    final campana = (await maestros.campanas()).first;
    final juan = (await maestros.operarios()).firstWhere((o) => o.id == idJuan);
    final mats = await maestros.buscarMateriales('');
    final l = await libros.crear(campana: campana, almacen: almacen, operario: juan);
    for (var i = 0; i < n; i++) {
      await libros.agregarMovimiento(
        libroId: l.id,
        material: mats[i % mats.length],
        cantidad: 10 + i,
        peso: 20.5 + i,
        observacion: i == 0 ? 'primero' : null,
        operarioId: juan.id,
      );
    }
    await libros.cerrar(l.id);
    return l;
  }

  group('descargarMaestros', () {
    test('guarda campañas, almacenes, materiales y operarios', () async {
      await sync.descargarMaestros();
      expect(await maestros.conteos(), {'almacenes': 1, 'campanas': 1, 'materiales': 2, 'operarios': 2});
      final juan = (await maestros.operarios()).firstWhere((o) => o.id == idJuan);
      expect(juan.pinHash, hashPin(idJuan, '1234'));
      expect(sync.descargando, isFalse);
    });

    test('compatibilidad: si el servidor manda el PIN en claro se guarda solo el hash', () async {
      final ops = (api.maestros['data'] as Map)['operarios'] as List;
      for (final o in ops.cast<Map<String, dynamic>>()) {
        o.remove('pin_hash');
        o['pin_seguridad'] = o['operario_id'] == idJuan ? '1234' : '4321';
      }
      await sync.descargarMaestros();
      final filas = await base.db.query('operarios');
      expect(filas.expand((f) => f.values), isNot(contains('1234')));
      final juan = (await maestros.operarios()).firstWhere((o) => o.id == idJuan);
      expect(juan.pinHash, hashPin(idJuan, '1234'));
    });

    test('descarta operarios sin PIN', () async {
      final ops = (api.maestros['data'] as Map)['operarios'] as List;
      (ops.first as Map).remove('pin_hash');
      await sync.descargarMaestros();
      expect((await maestros.operarios()).map((o) => o.id), [idMaria]);
    });

    test('si falla, propaga el error y conserva los datos anteriores', () async {
      await sync.descargarMaestros();
      api.errorDescarga = ApiException('caído', sinConexion: true);
      await expectLater(sync.descargarMaestros(), throwsA(isA<ApiException>()));
      expect((await maestros.conteos())['materiales'], 2);
      expect(sync.sesionInvalida, isFalse);
    });

    test('marca la sesión como inválida si el servidor la rechaza', () async {
      api.errorDescarga = ApiException('expiró', sesionInvalida: true, status: 401);
      await expectLater(sync.descargarMaestros(), throwsA(isA<ApiException>()));
      expect(sync.sesionInvalida, isTrue);
    });
  });

  group('enviarPendientes', () {
    setUp(() => sync.descargarMaestros());

    test('envía los libros cerrados con el contrato v2.1 y los marca enviados', () async {
      final l = await libroCerrado();
      await sync.refrescarPendientes();
      expect(sync.pendientes, 1);

      final r = await sync.enviarPendientes();
      expect(r.enviados, 1);
      expect(r.fallidos, 0);
      expect(sync.pendientes, 0);
      expect(sync.ultimoMensaje, '1 libro enviado.');
      expect(sync.ultimoEnvioOk, isNotNull);
      expect((await libros.porId(l.id))!.estado, EstadoLibro.enviado);

      final cuerpo = api.subidos.single;
      expect(cuerpo['libro_id'], l.id);
      expect(cuerpo['campana_id'], idCampana);
      expect(cuerpo['almacen_id'], idAlmacen1);
      expect(cuerpo['operario_id'], idJuan);
      expect(DateTime.parse(cuerpo['fecha_conteo'] as String).isUtc, isTrue);
      expect(cuerpo['fecha_cierre'], isNotNull);
      final detalles = (cuerpo['detalles'] as List).cast<Map<String, Object?>>();
      expect(detalles, hasLength(2));
      for (final d in detalles) {
        expect(d.keys.toSet(),
            {'movimiento_id', 'material_id', 'cantidad_unidad', 'peso_neto', 'observacion', 'fecha_registro'});
      }
    });

    test('los detalles se envían en el orden en que se capturaron', () async {
      final l = await libroCerrado(n: 3);
      final movs = await libros.movimientos(l.id);
      // Fechas explícitas para no depender de la resolución del reloj.
      final ascendente = movs.reversed.toList();
      for (var i = 0; i < ascendente.length; i++) {
        await base.db.update('movimientos', {'fecha_registro': '2026-10-18T10:0$i:00.000Z'},
            where: 'movimiento_id = ?', whereArgs: [ascendente[i].id]);
      }
      await sync.enviarPendientes();
      final fechas = (api.subidos.single['detalles'] as List)
          .map((d) => (d as Map)['fecha_registro'] as String)
          .toList();
      expect(fechas, [...fechas]..sort());
    });

    test('un reenvío que el servidor ya tenía cuenta como enviado (duplicado)', () async {
      final l = await libroCerrado();
      api.librosEnServidor.add(l.id);
      final r = await sync.enviarPendientes();
      expect(r.enviados, 1);
      expect(r.duplicados, 1);
      expect((await libros.porId(l.id))!.estado, EstadoLibro.enviado);
    });

    test('sin red no llama a la API y los libros quedan pendientes', () async {
      await libroCerrado();
      red.online = false;
      final r = await sync.enviarPendientes();
      expect(r.enviados, 0);
      expect(api.intentosSubida, 0);
      expect(sync.pendientes, 1);
      expect(sync.ultimoMensaje, contains('Sin conexión'));
    });

    test('si se cae la red a mitad, se detiene y registra el fallo', () async {
      final a = await libroCerrado();
      await libroCerrado(n: 1);
      api.errorSubida = (_) => ApiException('No se pudo conectar con el servidor.', sinConexion: true);

      final r = await sync.enviarPendientes();
      expect(r.fallidos, 1);
      expect(api.intentosSubida, 1, reason: 'no intenta el segundo libro');
      final fallido = (await libros.porId(a.id))!;
      expect(fallido.intentosSync, 1);
      expect(fallido.ultimoError, contains('No se pudo conectar'));
      expect(sync.pendientes, 2);
      expect(sync.ultimoFueError, isTrue);
    });

    test('un rechazo de negocio (403) no detiene el resto de la cola', () async {
      final malo = await libroCerrado();
      final bueno = await libroCerrado();
      api.errorSubida = (c) => c['libro_id'] == malo.id
          ? ApiException('La cuenta no puede registrar libros de otro almacén.', status: 403)
          : null;

      final r = await sync.enviarPendientes();
      expect(r.enviados, 1);
      expect(r.fallidos, 1);
      expect((await libros.porId(bueno.id))!.estado, EstadoLibro.enviado);
      expect((await libros.porId(malo.id))!.estado, EstadoLibro.pendienteEnvio);
      expect(sync.ultimoMensaje, contains('otro almacén'));
    });

    test('sesión inválida: se detiene y los envíos automáticos esperan reautenticación', () async {
      await libroCerrado();
      api.errorSubida = (_) => ApiException('expiró', sesionInvalida: true, status: 401);
      await sync.enviarPendientes();
      expect(sync.sesionInvalida, isTrue);

      api.errorSubida = null;
      final auto = await sync.enviarPendientes(automatico: true);
      expect(auto.enviados, 0);
      expect(api.intentosSubida, 1);

      sync.sesionInvalida = false;
      final manual = await sync.enviarPendientes();
      expect(manual.enviados, 1);
    });

    test('dos llamadas simultáneas comparten el mismo envío', () async {
      await libroCerrado();
      final f1 = sync.enviarPendientes();
      final f2 = sync.enviarPendientes();
      expect(sync.enviando, isTrue);
      expect(identical(f1, f2), isTrue);
      await Future.wait([f1, f2]);
      expect(api.intentosSubida, 1);
      expect(sync.enviando, isFalse);
    });

    test('al recuperar la red envía automáticamente', () async {
      await libroCerrado();
      red.online = false;
      await sync.refrescarPendientes();
      expect(api.intentosSubida, 0);

      red.online = true;
      await esperarHasta(() => api.subidos.length == 1);
      await esperarHasta(() => !sync.enviando);
      expect(sync.pendientes, 0);
    });

    test('un error inesperado no se escapa del envío', () async {
      await libroCerrado();
      await base.cerrar(); // la base deja de responder
      final r = await sync.enviarPendientes();
      expect(r.enviados, 0);
      expect(sync.ultimoFueError, isTrue);
      base = await abrirBaseEnMemoria(); // para el tearDown
    });
  });

  test('cuerpoDeEnvio usa fechas UTC', () {
    final l = Libro(
      id: 'l',
      campanaId: 'c',
      campanaNombre: 'C',
      almacenId: 'a',
      almacenNombre: 'A',
      operarioId: 'o',
      operarioNombre: 'O',
      fechaCreacion: DateTime.utc(2026, 10, 18, 19),
      fechaCierre: DateTime.utc(2026, 10, 18, 20, 30),
      estado: EstadoLibro.pendienteEnvio,
    );
    final c = SyncController.cuerpoDeEnvio(l, const []);
    expect(c['fecha_conteo'], '2026-10-18T19:00:00.000Z');
    expect(c['fecha_cierre'], '2026-10-18T20:30:00.000Z');
    expect(c['detalles'], isEmpty);
  });
}

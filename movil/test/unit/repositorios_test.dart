import 'package:flutter_test/flutter_test.dart';
import 'package:stex_inv_movil/data/local/database.dart';
import 'package:stex_inv_movil/data/repositories/libros_repository.dart';
import 'package:stex_inv_movil/data/repositories/maestros_repository.dart';
import 'package:stex_inv_movil/domain/models.dart';

import '../helpers/fakes.dart';

void main() {
  late AppDatabase base;
  late MaestrosRepository maestros;
  late LibrosRepository libros;
  late Almacen almacen1;
  late Almacen almacen2;
  late Campana campana;
  late Operario juan;
  late MaterialTextil hilo;
  late MaterialTextil jersey;

  Future<void> sembrar() async {
    final d = maestrosDeEjemplo(dosAlmacenes: true)['data'] as Map<String, dynamic>;
    List<Map<String, dynamic>> l(String k) => (d[k] as List).cast<Map<String, dynamic>>();
    await maestros.reemplazar(
      almacenes: l('almacenes').map(Almacen.fromJson).toList(),
      campanas: l('campanas').map(Campana.fromJson).toList(),
      materiales: l('materiales').map(MaterialTextil.fromJson).toList(),
      operarios: l('operarios').map(Operario.fromJson).toList(),
      timestampServidor: '2026-10-19T12:00:00Z',
    );
  }

  setUp(() async {
    base = await abrirBaseEnMemoria();
    maestros = MaestrosRepository(base.db);
    libros = LibrosRepository(base.db);
    await sembrar();
    final almacenes = await maestros.almacenes();
    almacen1 = almacenes.firstWhere((a) => a.id == idAlmacen1);
    almacen2 = almacenes.firstWhere((a) => a.id == idAlmacen2);
    campana = (await maestros.campanas()).single;
    juan = (await maestros.operarios()).firstWhere((o) => o.id == idJuan);
    final mats = await maestros.buscarMateriales('');
    hilo = mats.firstWhere((m) => m.id == idHilo);
    jersey = mats.firstWhere((m) => m.id == idJersey);
  });

  tearDown(() => base.cerrar());

  Future<Libro> nuevoLibro([Almacen? a]) =>
      libros.crear(campana: campana, almacen: a ?? almacen1, operario: juan);

  Future<void> registrar(Libro l, MaterialTextil m, {int cantidad = 10, double peso = 25, String? obs}) =>
      libros.agregarMovimiento(
        libroId: l.id,
        material: m,
        cantidad: cantidad,
        peso: peso,
        observacion: obs,
        operarioId: juan.id,
      );

  group('MaestrosRepository', () {
    test('reemplazar guarda todo y registra la fecha de descarga', () async {
      expect(await maestros.conteos(), {'almacenes': 2, 'campanas': 1, 'materiales': 2, 'operarios': 2});
      expect(await maestros.meta('ultima_descarga'), '2026-10-19T12:00:00Z');
    });

    test('reemplazar borra los maestros anteriores', () async {
      await maestros.reemplazar(
        almacenes: [almacen1],
        campanas: const [],
        materiales: [hilo],
        operarios: [juan],
        timestampServidor: 't2',
      );
      expect(await maestros.conteos(), {'almacenes': 1, 'campanas': 0, 'materiales': 1, 'operarios': 1});
    });

    test('si reemplazar falla, los datos anteriores quedan intactos (transacción)', () async {
      await expectLater(
        maestros.reemplazar(
          almacenes: [almacen1],
          campanas: const [],
          materiales: [hilo, hilo], // clave primaria duplicada
          operarios: const [],
          timestampServidor: 't3',
        ),
        throwsA(anything),
      );
      expect(await maestros.conteos(), {'almacenes': 2, 'campanas': 1, 'materiales': 2, 'operarios': 2});
      expect(await maestros.meta('ultima_descarga'), '2026-10-19T12:00:00Z');
    });

    test('buscarMateriales por código, kardex o descripción', () async {
      expect((await maestros.buscarMateriales('MAT-014')).map((m) => m.id), [idJersey]);
      expect((await maestros.buscarMateriales('1001')).map((m) => m.id), [idHilo]);
      expect((await maestros.buscarMateriales('jersey')).map((m) => m.id), [idJersey]);
      expect((await maestros.buscarMateriales('HILO')).map((m) => m.id), [idHilo]);
      expect(await maestros.buscarMateriales('no-existe'), isEmpty);
    });

    test('buscarMateriales pone primero la coincidencia exacta de código', () async {
      // "MAT-0" aparece en ambos; "MAT-001" exacto debe ir primero.
      final r = await maestros.buscarMateriales('MAT-001');
      expect(r.first.id, idHilo);
    });

    test('meta guarda, sobrescribe y acepta null', () async {
      await maestros.guardarMeta('x', '1');
      await maestros.guardarMeta('x', '2');
      expect(await maestros.meta('x'), '2');
      await maestros.guardarMeta('x', null);
      expect(await maestros.meta('x'), isNull);
      expect(await maestros.meta('no-existe'), isNull);
    });
  });

  group('LibrosRepository', () {
    test('crear deja un libro abierto con los nombres copiados', () async {
      final l = await nuevoLibro();
      expect(l.estado, EstadoLibro.abierto);
      expect(l.campanaNombre, 'Inventario Octubre 2026');
      expect(l.almacenNombre, 'Textiles del Norte S.A.C.');
      expect(l.operarioNombre, 'Juan Carlos Pérez');
      expect((await libros.abiertoDe(idAlmacen1))?.id, l.id);
      expect(await libros.abiertoDe(idAlmacen2), isNull);
    });

    test('solo un libro abierto por almacén', () async {
      await nuevoLibro();
      await expectLater(nuevoLibro(), throwsA(isA<ReglaNegocioException>()));
      // En otro almacén sí se puede.
      expect((await nuevoLibro(almacen2)).almacenId, idAlmacen2);
    });

    test('agregarMovimiento guarda los datos y los totales del libro', () async {
      final l = await nuevoLibro();
      await registrar(l, hilo, cantidad: 45, peso: 112.75, obs: '  caja verde  ');
      await registrar(l, jersey, cantidad: 10, peso: 25, obs: '   ');

      final movs = await libros.movimientos(l.id);
      expect(movs, hasLength(2));
      final mHilo = movs.firstWhere((m) => m.materialId == idHilo);
      expect(mHilo.cantidad, 45);
      expect(mHilo.peso, 112.75);
      expect(mHilo.observacion, 'caja verde');
      expect(mHilo.materialCodigo, 'MAT-001');
      expect(mHilo.operarioId, idJuan);
      expect(movs.firstWhere((m) => m.materialId == idJersey).observacion, isNull);

      final actualizado = (await libros.porId(l.id))!;
      expect(actualizado.totalItems, 2);
      expect(actualizado.pesoTotal, closeTo(137.75, 1e-9));
    });

    test('un registro inválido no deja nada escrito', () async {
      final l = await nuevoLibro();
      await expectLater(registrar(l, hilo, cantidad: -1), throwsA(anything));
      expect(await libros.movimientos(l.id), isEmpty);
    });

    test('eliminarMovimiento solo en libros abiertos', () async {
      final l = await nuevoLibro();
      await registrar(l, hilo);
      await registrar(l, jersey);
      final movs = await libros.movimientos(l.id);
      await libros.eliminarMovimiento(movs.first);
      expect(await libros.movimientos(l.id), hasLength(1));

      await libros.cerrar(l.id);
      final restante = (await libros.movimientos(l.id)).single;
      await expectLater(libros.eliminarMovimiento(restante), throwsA(isA<ReglaNegocioException>()));
    });

    test('cerrar exige registros y deja el libro en cola de envío', () async {
      final l = await nuevoLibro();
      await expectLater(libros.cerrar(l.id), throwsA(isA<ReglaNegocioException>()));

      await registrar(l, hilo);
      await libros.cerrar(l.id);
      final cerrado = (await libros.porId(l.id))!;
      expect(cerrado.estado, EstadoLibro.pendienteEnvio);
      expect(cerrado.fechaCierre, isNotNull);
      expect(await libros.contarPendientes(), 1);
      expect(await libros.abiertoDe(idAlmacen1), isNull);

      await expectLater(registrar(l, jersey), throwsA(isA<ReglaNegocioException>()));
    });

    test('reabrir un pendiente; no si ya hay otro abierto o si ya se envió', () async {
      final l = await nuevoLibro();
      await registrar(l, hilo);
      await libros.cerrar(l.id);

      final otro = await nuevoLibro();
      await expectLater(libros.reabrir((await libros.porId(l.id))!),
          throwsA(isA<ReglaNegocioException>()));
      await libros.descartarVacio(otro.id);

      await libros.reabrir((await libros.porId(l.id))!);
      expect((await libros.porId(l.id))!.estado, EstadoLibro.abierto);

      await libros.cerrar(l.id);
      await libros.marcarEnviado(l.id);
      await expectLater(libros.reabrir((await libros.porId(l.id))!),
          throwsA(isA<ReglaNegocioException>()));
    });

    test('descartarVacio borra solo libros sin registros', () async {
      final l = await nuevoLibro();
      await registrar(l, hilo);
      await expectLater(libros.descartarVacio(l.id), throwsA(isA<ReglaNegocioException>()));
      final m = (await libros.movimientos(l.id)).single;
      await libros.eliminarMovimiento(m);
      await libros.descartarVacio(l.id);
      expect(await libros.porId(l.id), isNull);
    });

    test('registrarFallo acumula intentos y guarda el último error', () async {
      final l = await nuevoLibro();
      await registrar(l, hilo);
      await libros.cerrar(l.id);
      await libros.registrarFallo(l.id, 'timeout');
      await libros.registrarFallo(l.id, 'HTTP 500');
      final r = (await libros.porId(l.id))!;
      expect(r.intentosSync, 2);
      expect(r.ultimoError, 'HTTP 500');

      await libros.marcarEnviado(l.id);
      final enviado = (await libros.porId(l.id))!;
      expect(enviado.estado, EstadoLibro.enviado);
      expect(enviado.ultimoError, isNull);
      expect(enviado.fechaEnvio, isNotNull);
    });

    test('purgarEnviados borra libros enviados hace más de N días y sus registros', () async {
      final viejo = await nuevoLibro();
      await registrar(viejo, hilo);
      await libros.cerrar(viejo.id);
      await libros.marcarEnviado(viejo.id);
      await base.db.update('libros', {'fecha_envio': '2026-01-01T00:00:00.000Z'},
          where: 'libro_id = ?', whereArgs: [viejo.id]);

      final reciente = await nuevoLibro();
      await registrar(reciente, hilo);
      await libros.cerrar(reciente.id);
      await libros.marcarEnviado(reciente.id);

      final pendiente = await nuevoLibro();
      await registrar(pendiente, jersey);
      await libros.cerrar(pendiente.id);

      expect(await libros.purgarEnviados(7), 1);
      expect(await libros.porId(viejo.id), isNull);
      expect(await libros.movimientos(viejo.id), isEmpty, reason: 'ON DELETE CASCADE');
      expect(await libros.porId(reciente.id), isNotNull);
      expect(await libros.porId(pendiente.id), isNotNull);
    });

    test('contarSinEnviar cuenta abiertos y pendientes, no enviados', () async {
      final a = await nuevoLibro();
      await registrar(a, hilo);
      await libros.cerrar(a.id);
      await libros.marcarEnviado(a.id);
      final b = await nuevoLibro();
      await registrar(b, hilo);
      await libros.cerrar(b.id);
      await nuevoLibro();
      expect(await libros.contarSinEnviar(), 2);
    });
  });
}

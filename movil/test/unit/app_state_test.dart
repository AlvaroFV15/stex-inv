import 'package:flutter_test/flutter_test.dart';
import 'package:stex_inv_movil/data/remote/api_client.dart';
import 'package:stex_inv_movil/domain/models.dart';
import 'package:stex_inv_movil/state/app_state.dart';

import '../helpers/fakes.dart';

void main() {
  late Banco banco;
  late AppState app;

  setUp(() {
    banco = Banco();
    app = banco.crearApp();
  });

  tearDown(() => app.liberar());

  Future<void> vincular() => app.vincular(correo, password);

  Operario juan() => Operario.fromJson({
        'operario_id': idJuan,
        'nombre_completo': 'Juan Carlos Pérez',
        'almacen_id': idAlmacen1,
        'pin_hash':
            ((banco.api.maestros['data'] as Map)['operarios'] as List).first['pin_hash'] as String,
      });

  group('arranque', () {
    test('sin configuración de compilación → configFaltante', () async {
      app = Banco(configCompleta: false).crearApp();
      await app.iniciar();
      expect(app.fase, Fase.configFaltante);
    });

    test('si la base no abre → errorBaseLocal con el detalle', () async {
      app = AppState(
        conectividad: banco.red,
        auth: banco.auth,
        api: banco.api,
        seguro: banco.seguro,
        abrirBase: (_) async => throw Exception('file is not a database'),
        eliminarBase: () async {},
        esperarFrame: () async {},
      );
      await app.iniciar();
      expect(app.fase, Fase.errorBaseLocal);
      expect(app.detalleError, contains('file is not a database'));
    });

    test('dispositivo nuevo → sinVincular', () async {
      await app.iniciar();
      expect(app.fase, Fase.sinVincular);
    });
  });

  group('vinculación (pasos 1 y 2)', () {
    setUp(() => app.iniciar());

    test('sin red no se puede vincular', () async {
      banco.red.online = false;
      await expectLater(vincular(),
          throwsA(isA<ApiException>().having((e) => e.sinConexion, 'sinConexion', isTrue)));
      expect(app.fase, Fase.sinVincular);
    });

    test('credenciales incorrectas', () async {
      await expectLater(app.vincular(correo, 'mala'),
          throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'Correo o contraseña incorrectos.')));
      expect(app.fase, Fase.sinVincular);
      expect(banco.api.descargas, 0);
    });

    test('si la descarga falla se cierra la sesión y no queda vinculado', () async {
      banco.api.errorDescarga = ApiException('La cuenta no tiene un almacén asignado.', status: 403);
      await expectLater(vincular(), throwsA(isA<ApiException>()));
      expect(banco.auth.token, isNull);
      expect(banco.seguro.email, isNull);
      expect(app.fase, Fase.sinVincular);
    });

    test('vincula, descarga maestros y pasa a elegir operario', () async {
      await vincular();
      expect(app.fase, Fase.sinOperario);
      expect(app.emailVinculado, correo);
      expect(banco.seguro.email, correo);
      expect(app.almacenes.map((a) => a.id), [idAlmacen1]);
      expect(app.almacenId, idAlmacen1);
      expect(await app.maestros.meta('vinculado'), '1');
    });

    test('al reiniciar la app ya no pide la contraseña', () async {
      await vincular();
      await app.liberar();

      app = banco.crearApp();
      await app.iniciar();
      expect(app.fase, Fase.sinOperario);
      expect(banco.api.descargas, 1, reason: 'no vuelve a descargar ni a pedir login');
    });
  });

  group('PIN (paso 3, offline)', () {
    setUp(() async {
      await app.iniciar();
      await vincular();
      banco.red.online = false; // el PIN no necesita red
    });

    test('PIN correcto inicia el turno', () {
      final r = app.ingresar(juan(), '1234');
      expect(r.ok, isTrue);
      expect(app.fase, Fase.listo);
      expect(app.operario?.id, idJuan);
      expect(app.almacenId, idAlmacen1);
    });

    test('PIN incorrecto descuenta intentos y bloquea al quinto', () {
      for (var i = 1; i <= 4; i++) {
        final r = app.ingresar(juan(), '0000');
        expect(r.ok, isFalse);
        expect(r.mensaje, 'PIN incorrecto. Te quedan ${5 - i} intentos.');
      }
      final quinto = app.ingresar(juan(), '0000');
      expect(quinto.mensaje, contains('Bloqueado por 60 s'));

      // Bloqueado: ni el PIN correcto entra.
      final bloqueado = app.ingresar(juan(), '1234');
      expect(bloqueado.ok, isFalse);
      expect(bloqueado.mensaje, contains('Demasiados intentos'));
      expect(app.fase, Fase.sinOperario);

      banco.reloj = banco.reloj.add(const Duration(seconds: 61));
      expect(app.ingresar(juan(), '1234').ok, isTrue);
    });

    test('un acierto reinicia el contador de fallos', () {
      app.ingresar(juan(), '0000');
      app.ingresar(juan(), '0000');
      expect(app.ingresar(juan(), '1234').ok, isTrue);
      app.cerrarTurno();
      expect(app.ingresar(juan(), '0000').mensaje, 'PIN incorrecto. Te quedan 4 intentos.');
    });

    test('cerrarTurno vuelve a la selección de operario', () {
      app.ingresar(juan(), '1234');
      app.cerrarTurno();
      expect(app.fase, Fase.sinOperario);
      expect(app.operario, isNull);
    });
  });

  group('almacén favorito', () {
    test('se guarda en el dispositivo y se usa al entrar', () async {
      banco.api.maestros = maestrosDeEjemplo(dosAlmacenes: true);
      await app.iniciar();
      await vincular();
      app.ingresar(juan(), '1234');
      expect(app.almacenId, idAlmacen1, reason: 'sin favorito usa el del operario');

      app.seleccionarAlmacen(idAlmacen2);
      await app.alternarFavorito();
      expect(app.almacenFavoritoId, idAlmacen2);

      await app.liberar();
      app = banco.crearApp();
      await app.iniciar();
      app.ingresar(juan(), '1234');
      expect(app.almacenId, idAlmacen2);

      await app.alternarFavorito();
      expect(app.almacenFavoritoId, isNull);
    });
  });

  group('persistencia (HU-07)', () {
    test('los registros sobreviven a cerrar y reabrir la app', () async {
      await app.iniciar();
      await vincular();
      app.ingresar(juan(), '1234');
      final campana = (await app.maestros.campanas()).single;
      final libro = await app.libros.crear(campana: campana, almacen: app.almacenActual!, operario: app.operario!);
      final hilo = (await app.maestros.buscarMateriales('MAT-001')).single;
      await app.libros.agregarMovimiento(
          libroId: libro.id, material: hilo, cantidad: 45, peso: 112.75, observacion: null, operarioId: idJuan);

      await app.liberar(); // equivale a matar la app
      app = banco.crearApp();
      await app.iniciar();

      final reabierto = await app.libros.abiertoDe(idAlmacen1);
      expect(reabierto?.id, libro.id);
      final movs = await app.libros.movimientos(libro.id);
      expect(movs.single.peso, 112.75);
    });

    test('al arrancar con red envía lo que quedó pendiente', () async {
      await app.iniciar();
      await vincular();
      app.ingresar(juan(), '1234');
      final campana = (await app.maestros.campanas()).single;
      final libro = await app.libros.crear(campana: campana, almacen: app.almacenActual!, operario: app.operario!);
      final hilo = (await app.maestros.buscarMateriales('MAT-001')).single;
      await app.libros.agregarMovimiento(
          libroId: libro.id, material: hilo, cantidad: 1, peso: 1, observacion: null, operarioId: idJuan);
      banco.red.online = false;
      await app.libros.cerrar(libro.id);
      await app.liberar();

      banco.red.online = true;
      app = banco.crearApp();
      await app.iniciar();
      await esperarHasta(() => banco.api.subidos.length == 1);
      await esperarHasta(() => !app.sync.enviando);
      expect((await app.libros.porId(libro.id))!.estado, EstadoLibro.enviado);
    });
  });

  group('sesión y desvinculación', () {
    setUp(() async {
      await app.iniciar();
      await vincular();
    });

    test('reautenticar limpia la sesión inválida y envía lo pendiente', () async {
      app.sync.sesionInvalida = true;
      await app.reautenticar(password);
      expect(app.sync.sesionInvalida, isFalse);
      expect(banco.auth.token, isNotNull);
    });

    test('reautenticar con contraseña incorrecta mantiene el aviso', () async {
      app.sync.sesionInvalida = true;
      await expectLater(app.reautenticar('mala'), throwsA(isA<ApiException>()));
      expect(app.sync.sesionInvalida, isTrue);
    });

    test('actualizarMaestros recarga los almacenes', () async {
      banco.api.maestros = maestrosDeEjemplo(dosAlmacenes: true);
      await app.actualizarMaestros();
      expect(app.almacenes, hasLength(2));
    });

    test('desvincular borra base, sesión y claves', () async {
      await app.desvincular();
      expect(banco.base.eliminaciones, 1);
      expect(banco.seguro.borrados, 1);
      expect(banco.auth.token, isNull);
      expect(app.fase, Fase.sinVincular);
      expect(app.emailVinculado, isNull);
      expect(app.almacenes, isEmpty);
      expect(await app.maestros.conteos(), {'almacenes': 0, 'campanas': 0, 'materiales': 0, 'operarios': 0});
    });
  });
}

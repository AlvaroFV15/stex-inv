import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stex_inv_movil/app.dart';
import 'package:stex_inv_movil/domain/models.dart';
import 'package:stex_inv_movil/state/app_state.dart';

import '../helpers/fakes.dart';

/// Pruebas de la app completa (todas las pantallas) con dobles de prueba:
/// base SQLite real en archivo temporal, API y Auth falsas.

Future<void> pumpHasta(WidgetTester t, Finder f, {int max = 100}) async {
  for (var i = 0; i < max; i++) {
    await t.pump(const Duration(milliseconds: 50));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('No apareció: $f');
}

Future<void> pumpMientras(WidgetTester t, bool Function() condicion, {int max = 100}) async {
  for (var i = 0; i < max && condicion(); i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  if (condicion()) throw TestFailure('La condición sigue siendo verdadera');
}

Future<void> tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump();
}

void main() {
  late Banco banco;
  late AppState app;

  /// Pantalla de teléfono: 400 x 1000 dp.
  void tamanoTelefono(WidgetTester t) {
    t.view.physicalSize = const Size(1200, 3000);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
  }

  Future<void> arrancar(WidgetTester t) async {
    tamanoTelefono(t);
    banco = Banco();
    app = banco.crearApp(esperarFrameReal: true);
    await t.pumpWidget(StexRaiz(conectividad: banco.red, app: app));
    final inicio = app.iniciar();
    await pumpHasta(t, find.text('Vincular dispositivo'));
    await inicio;
  }

  Future<void> vincularYEntrar(WidgetTester t, {String pin = '1234'}) async {
    await t.enterText(find.byKey(const Key('campo-email')), correo);
    await t.enterText(find.byKey(const Key('campo-password')), password);
    await tocar(t, find.byKey(const Key('btn-vincular')));
    await pumpHasta(t, find.text('¿Quién inicia turno?'));

    await tocar(t, find.byKey(const Key('operario-$idJuan')));
    await pumpHasta(t, find.text('Ingresa tu PIN'));
    for (final d in pin.split('')) {
      await t.tap(find.byKey(Key('tecla-$d')));
      await t.pump();
    }
    await t.pump(const Duration(milliseconds: 200));
  }

  Future<void> registrar(WidgetTester t, String materialId, String cantidad, String peso) async {
    await tocar(t, find.byKey(const Key('campo-material')));
    await pumpHasta(t, find.byKey(Key('material-$materialId')));
    await t.tap(find.byKey(Key('material-$materialId')));
    await pumpHasta(t, find.text('Nuevo registro'));
    await t.enterText(find.byKey(const Key('campo-cantidad')), cantidad);
    await t.enterText(find.byKey(const Key('campo-peso')), peso);
    await tocar(t, find.byKey(const Key('btn-registrar')));
  }

  Future<void> terminar(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await app.liberar();
    await t.pump();
  }

  testWidgets('flujo completo: vincular → PIN → crear libro → registrar → cerrar → enviar',
      (t) async {
    await arrancar(t);
    await vincularYEntrar(t);

    // Pantalla del mockup.
    await pumpHasta(t, find.text('No hay libro de conteo activo'));
    expect(find.text('Panel de Conteo y Captura'), findsOneWidget);
    expect(find.text('Textiles del Norte S.A.C.'), findsWidgets);

    await tocar(t, find.byKey(const Key('btn-crear-libro')));
    await pumpHasta(t, find.text('Nuevo registro'));
    expect(find.text('Inventario Octubre 2026'), findsOneWidget);

    await registrar(t, idHilo, '45', '112.75');
    await pumpHasta(t, find.text('Registrados (1)'));

    // Más de 150 kg pide confirmación.
    await registrar(t, idJersey, '3', '200');
    await pumpHasta(t, find.text('Peso alto'));
    await t.tap(find.text('Sí, guardar'));
    await pumpHasta(t, find.text('Registrados (2)'));
    expect(find.text('2 registros · 312.75 kg'), findsOneWidget);

    await tocar(t, find.byKey(const Key('btn-cerrar-libro')));
    await pumpHasta(t, find.byKey(const Key('btn-confirmar-cierre')));
    await t.tap(find.byKey(const Key('btn-confirmar-cierre')));
    await pumpHasta(t, find.text('No hay libro de conteo activo'));

    // Con red, se envía solo.
    await pumpMientras(t, () => banco.api.subidos.isEmpty);
    final enviado = banco.api.subidos.single;
    expect(enviado['operario_id'], idJuan);
    expect((enviado['detalles'] as List).length, 2);
    await pumpMientras(t, () => app.sync.enviando);
    final libros = await app.libros.todos();
    expect(libros.single.estado, EstadoLibro.enviado);

    await terminar(t);
  });

  testWidgets('sin red: se guarda en el dispositivo y se envía al volver la conexión', (t) async {
    await arrancar(t);
    await vincularYEntrar(t);
    await pumpHasta(t, find.text('No hay libro de conteo activo'));

    banco.red.online = false;
    await t.pump();
    expect(find.textContaining('Modo offline'), findsOneWidget);

    await tocar(t, find.byKey(const Key('btn-crear-libro')));
    await pumpHasta(t, find.text('Nuevo registro'));
    await registrar(t, idHilo, '10', '25');
    await pumpHasta(t, find.text('Registrados (1)'));

    await tocar(t, find.byKey(const Key('btn-cerrar-libro')));
    await pumpHasta(t, find.byKey(const Key('btn-confirmar-cierre')));
    await t.tap(find.byKey(const Key('btn-confirmar-cierre')));
    await pumpHasta(t, find.text('Libro cerrado. Se enviará cuando haya conexión.'));
    expect(banco.api.subidos, isEmpty);
    expect(app.sync.pendientes, 1);

    banco.red.online = true;
    await pumpMientras(t, () => banco.api.subidos.isEmpty);
    await pumpMientras(t, () => app.sync.pendientes > 0);
    expect(find.textContaining('Modo offline'), findsNothing);

    await terminar(t);
  });

  testWidgets('PIN incorrecto muestra los intentos restantes', (t) async {
    await arrancar(t);
    await vincularYEntrar(t, pin: '9999');
    await pumpHasta(t, find.text('PIN incorrecto. Te quedan 4 intentos.'));
    expect(app.fase, Fase.sinOperario);
    await terminar(t);
  });

  testWidgets('credenciales incorrectas se muestran en la pantalla de vinculación', (t) async {
    await arrancar(t);
    await t.enterText(find.byKey(const Key('campo-email')), correo);
    await t.enterText(find.byKey(const Key('campo-password')), 'mala');
    await tocar(t, find.byKey(const Key('btn-vincular')));
    await pumpHasta(t, find.text('Correo o contraseña incorrectos.'));
    expect(app.fase, Fase.sinVincular);
    await terminar(t);
  });

  testWidgets('desvincular avisa si hay libros sin enviar', (t) async {
    await arrancar(t);
    await vincularYEntrar(t);
    await pumpHasta(t, find.text('No hay libro de conteo activo'));
    await tocar(t, find.byKey(const Key('btn-crear-libro')));
    await pumpHasta(t, find.text('Nuevo registro'));

    await t.tap(find.text('Perfil'));
    await pumpHasta(t, find.text('Desvincular dispositivo'));
    await tocar(t, find.text('Desvincular dispositivo'));
    await pumpHasta(t, find.textContaining('no llegaron al servidor'));
    await t.tap(find.text('Cancelar'));
    await t.pump(const Duration(milliseconds: 300));
    expect(app.fase, Fase.listo);
    await terminar(t);
  });
}

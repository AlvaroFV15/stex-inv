import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stex_inv_movil/main.dart' as app;

/// Prueba de punta a punta en un emulador o celular real, contra el
/// servidor local de Docker.
///
///   docker compose up -d db api
///   flutter test integration_test --dart-define-from-file=dart_defines.docker.json
///
/// Usa la app real: SQLCipher, Keystore/Keychain, Supabase Auth y la API.

const _correo = 'almacen1@apjltextil.com';
const _password = 'Stex2026!';
const _juan = 'd1000000-0000-4000-8000-000000000001';
const _hilo = 'b1000000-0000-4000-8000-000000000001';

/// Espera en tiempo real (aquí hay E/S real: base cifrada, red).
Future<void> esperar(WidgetTester t, Finder f, {Duration limite = const Duration(seconds: 30)}) async {
  final fin = DateTime.now().add(limite);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(fin)) throw TestFailure('No apareció: $f');
    await t.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('vincular → PIN → libro → registro → cerrar → envío → desvincular', (t) async {
    await app.main();
    await esperar(t, find.byWidgetPredicate((w) =>
        w is Text && (w.data == 'Vincular dispositivo' || w.data == '¿Quién inicia turno?')));

    if (find.text('Vincular dispositivo').evaluate().isNotEmpty) {
      await t.enterText(find.byKey(const Key('campo-email')), _correo);
      await t.enterText(find.byKey(const Key('campo-password')), _password);
      await tocar(t, find.byKey(const Key('btn-vincular')));
    }

    await esperar(t, find.byKey(const Key('operario-$_juan')));
    await tocar(t, find.byKey(const Key('operario-$_juan')));
    await esperar(t, find.text('Ingresa tu PIN'));
    for (final d in '1234'.split('')) {
      await t.tap(find.byKey(Key('tecla-$d')));
      await t.pump();
    }

    await esperar(t, find.text('Panel de Conteo y Captura'));
    // Si quedó un libro abierto de una corrida anterior, se reutiliza.
    await esperar(t, find.byWidgetPredicate((w) =>
        w is Text && (w.data == 'No hay libro de conteo activo' || w.data == 'Nuevo registro')));
    if (find.byKey(const Key('btn-crear-libro')).evaluate().isNotEmpty) {
      await tocar(t, find.byKey(const Key('btn-crear-libro')));
      await esperar(t, find.text('Nuevo registro'));
    }

    await tocar(t, find.byKey(const Key('campo-material')));
    await esperar(t, find.byKey(const Key('material-$_hilo')));
    await t.tap(find.byKey(const Key('material-$_hilo')));
    await esperar(t, find.text('Nuevo registro'));
    await t.enterText(find.byKey(const Key('campo-cantidad')), '12');
    await t.enterText(find.byKey(const Key('campo-peso')), '30.5');
    await tocar(t, find.byKey(const Key('btn-registrar')));
    await esperar(t, find.textContaining('Registrado:'));

    await tocar(t, find.byKey(const Key('btn-cerrar-libro')));
    await esperar(t, find.byKey(const Key('btn-confirmar-cierre')));
    await t.tap(find.byKey(const Key('btn-confirmar-cierre')));
    await esperar(t, find.text('No hay libro de conteo activo'));

    // Pestaña Sync: el libro debe quedar enviado.
    await t.tap(find.text('Sync'));
    await esperar(t, find.text('No hay libros pendientes de envío.'), limite: const Duration(seconds: 60));

    // Deja el dispositivo limpio para la próxima corrida.
    await t.tap(find.text('Perfil'));
    await esperar(t, find.text('Desvincular dispositivo'));
    await tocar(t, find.text('Desvincular dispositivo'));
    await esperar(t, find.text('Desvincular'));
    await t.tap(find.text('Desvincular'));
    await esperar(t, find.text('Vincular dispositivo'));
  });
}

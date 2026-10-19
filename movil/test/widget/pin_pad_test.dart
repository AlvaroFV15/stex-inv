import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stex_inv_movil/ui/widgets/estado_chip.dart';
import 'package:stex_inv_movil/ui/widgets/pin_pad.dart';
import 'package:stex_inv_movil/domain/models.dart';

Widget _envolver(Widget hijo) => MaterialApp(home: Scaffold(body: Center(child: hijo)));

void main() {
  testWidgets('PinPad entrega el PIN al completar 4 dígitos', (tester) async {
    String? recibido;
    await tester.pumpWidget(_envolver(PinPad(alCompletar: (p) => recibido = p)));

    for (final d in ['1', '2', '3']) {
      await tester.tap(find.byKey(Key('tecla-$d')));
      await tester.pump();
    }
    expect(recibido, isNull);

    await tester.tap(find.byKey(const Key('tecla-4')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(recibido, '1234');
  });

  testWidgets('la tecla borrar quita el último dígito', (tester) async {
    String? recibido;
    await tester.pumpWidget(_envolver(PinPad(alCompletar: (p) => recibido = p)));
    for (final k in ['tecla-9', 'tecla-9', 'tecla-borrar', 'tecla-1', 'tecla-2', 'tecla-3']) {
      await tester.tap(find.byKey(Key(k)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(recibido, '9123');
  });

  testWidgets('no acepta más dígitos que la longitud ni teclas deshabilitadas', (tester) async {
    final recibidos = <String>[];
    await tester.pumpWidget(_envolver(PinPad(alCompletar: recibidos.add)));
    for (final d in ['1', '1', '1', '1', '2', '2']) {
      await tester.tap(find.byKey(Key('tecla-$d')));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(recibidos, ['1111']);

    await tester.pumpWidget(_envolver(PinPad(habilitado: false, alCompletar: recibidos.add)));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('tecla-5')));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(recibidos, ['1111']);
  });

  testWidgets('muestra el mensaje de error', (tester) async {
    await tester.pumpWidget(_envolver(PinPad(alCompletar: (_) {}, error: 'PIN incorrecto.')));
    expect(find.text('PIN incorrecto.'), findsOneWidget);
  });

  testWidgets('las teclas miden al menos 48 dp (guía táctil de planta)', (tester) async {
    await tester.pumpWidget(_envolver(PinPad(alCompletar: (_) {})));
    final tam = tester.getSize(find.byKey(const Key('tecla-5')));
    expect(tam.width, greaterThanOrEqualTo(48));
    expect(tam.height, greaterThanOrEqualTo(48));
  });

  testWidgets('EstadoChip muestra el estado y el error de envío', (tester) async {
    await tester.pumpWidget(_envolver(const Column(children: [
      EstadoChip(EstadoLibro.abierto),
      EstadoChip(EstadoLibro.pendienteEnvio),
      EstadoChip(EstadoLibro.pendienteEnvio, conError: true),
      EstadoChip(EstadoLibro.enviado),
    ])));
    expect(find.text('Abierto'), findsOneWidget);
    expect(find.text('Pendiente de envío'), findsOneWidget);
    expect(find.text('Error al enviar'), findsOneWidget);
    expect(find.text('Enviado'), findsOneWidget);
  });
}

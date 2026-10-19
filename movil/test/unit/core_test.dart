import 'package:flutter_test/flutter_test.dart';
import 'package:stex_inv_movil/core/formato.dart';
import 'package:stex_inv_movil/core/pin_hash.dart';
import 'package:stex_inv_movil/data/local/secure_store.dart';
import 'package:stex_inv_movil/data/remote/auth_service.dart';
import 'package:stex_inv_movil/domain/models.dart';

void main() {
  group('hashPin', () {
    test('coincide con el hash del servidor (vector compartido con backend)', () {
      expect(
        hashPin('8d9e0f1a-2b3c-4d5e-6f7a-8b9c0d1e2f3a', '1234'),
        '5d073a17585244f3a25ca8c8e7bd695507a736ebce0ff416f8a6d284f17a8e29',
      );
    });

    test('el mismo PIN da hashes distintos para operarios distintos', () {
      expect(hashPin('a', '1234'), isNot(hashPin('b', '1234')));
    });
  });

  group('formato', () {
    test('parsePeso acepta coma o punto y rechaza texto', () {
      expect(parsePeso('112,75'), 112.75);
      expect(parsePeso(' 25.5 '), 25.5);
      expect(parsePeso('abc'), isNull);
      expect(parsePeso(''), isNull);
    });

    test('kg muestra dos decimales', () {
      expect(kg(112.754), '112.75 kg');
      expect(kg(0), '0.00 kg');
    });

    test('fechaHora y hora en hora local', () {
      final d = DateTime(2026, 10, 18, 9, 5);
      expect(fechaHora(d), '18/10/2026 09:05');
      expect(hora(d), '09:05');
    });

    test('ahoraIso es UTC e ISO 8601', () {
      final s = ahoraIso();
      expect(s.endsWith('Z'), isTrue);
      expect(DateTime.tryParse(s), isNotNull);
    });
  });

  group('modelos', () {
    test('Campana acepta campana_id y campanas_id (nombre de columna del panel)', () {
      expect(Campana.fromJson({'campanas_id': 'x', 'nombre': 'Oct'}).id, 'x');
      expect(Campana.fromJson({'campana_id': 'y', 'nombre': 'Oct'}).id, 'y');
    });

    test('MaterialTextil acepta codigo_material y codigo_interno', () {
      expect(MaterialTextil.fromJson({'codigo_material': 'M1', 'descripcion': 'd'}).codigo, 'M1');
      expect(MaterialTextil.fromJson({'codigo_interno': 'M2', 'descripcion': 'd'}).codigo, 'M2');
    });

    test('MaterialTextil.detalle junta código, kardex y tipo', () {
      const m = MaterialTextil(id: '1', codigo: 'MAT-001', kardex: '1001', descripcion: 'Hilo', tipo: 'Hilo');
      expect(m.detalle, 'MAT-001 · Kardex 1001 · Hilo');
    });

    test('ida y vuelta por SQLite conserva los datos', () {
      const a = Almacen(id: 'a', codigo: 'TEJ04', nro: '9', razonSocial: 'Textiles', nombreLocal: 'Planta');
      final a2 = Almacen.fromDb(a.toDb());
      expect([a2.id, a2.codigo, a2.nro, a2.razonSocial, a2.nombreLocal], ['a', 'TEJ04', '9', 'Textiles', 'Planta']);

      const o = Operario(id: 'o', nombre: 'Juan', pinHash: 'h', almacenId: 'a');
      final o2 = Operario.fromDb(o.toDb());
      expect([o2.id, o2.nombre, o2.pinHash, o2.almacenId], ['o', 'Juan', 'h', 'a']);
    });

    test('Almacen.nombre usa razón social o, si falta, el nombre del local', () {
      const conRazon = Almacen(id: '1', codigo: '', nro: '9', razonSocial: 'Textiles', nombreLocal: 'Planta');
      const sinRazon = Almacen(id: '2', codigo: '', nro: '', razonSocial: '', nombreLocal: 'Planta');
      expect(conRazon.nombre, 'Textiles');
      expect(conRazon.detalle, 'Alm. 9 · Planta');
      expect(sinRazon.nombre, 'Planta');
      expect(sinRazon.detalle, '');
    });

    test('Operario.iniciales', () {
      const o = Operario(id: '1', nombre: 'Juan Carlos Pérez', pinHash: 'h', almacenId: 'a');
      expect(o.iniciales, 'JC');
      const uno = Operario(id: '2', nombre: '  maría ', pinHash: 'h', almacenId: 'a');
      expect(uno.iniciales, 'M');
    });

    test('EstadoLibro.desdeDb con valor desconocido vuelve a abierto', () {
      expect(EstadoLibro.desdeDb('PENDIENTE_ENVIO'), EstadoLibro.pendienteEnvio);
      expect(EstadoLibro.desdeDb('ENVIADO'), EstadoLibro.enviado);
      expect(EstadoLibro.desdeDb('raro'), EstadoLibro.abierto);
      expect(EstadoLibro.desdeDb(null), EstadoLibro.abierto);
    });

    test('Movimiento.toApi tiene el formato del contrato v2.1', () {
      final m = Movimiento.fromDb({
        'movimiento_id': 'mv1',
        'libro_id': 'l1',
        'material_id': 'm1',
        'material_codigo': 'MAT-001',
        'material_descripcion': 'Hilo',
        'cantidad_unidad': 45,
        'peso_neto': 112.75,
        'observacion': null,
        'fecha_registro': '2026-10-18T19:05:00.000Z',
        'operario_id': 'o1',
      });
      expect(m.toApi(), {
        'movimiento_id': 'mv1',
        'material_id': 'm1',
        'cantidad_unidad': 45,
        'peso_neto': 112.75,
        'observacion': null,
        'fecha_registro': '2026-10-18T19:05:00.000Z',
      });
    });
  });

  group('seguridad', () {
    test('generarClave produce 64 caracteres hex distintos cada vez', () {
      final a = SecureStore.generarClave();
      final b = SecureStore.generarClave();
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a, isNot(b));
    });

    test('traducirErrorAuth pasa los mensajes de Supabase a español', () {
      expect(traducirErrorAuth('Invalid login credentials'), 'Correo o contraseña incorrectos.');
      expect(traducirErrorAuth('Email not confirmed'), 'La cuenta no está confirmada.');
      expect(traducirErrorAuth('SocketException: Failed host lookup'), 'No se pudo conectar con el servidor.');
      expect(traducirErrorAuth('otro'), 'otro');
    });
  });
}

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/models.dart';

/// Datos maestros que baja el dispositivo (almacenes, campañas, materiales,
/// operarios) y pequeños valores de configuración en la tabla `meta`.
class MaestrosRepository {
  MaestrosRepository(this._db);
  final Database _db;

  /// Reemplaza todos los maestros en una sola transacción: si algo falla,
  /// el dispositivo se queda con los datos anteriores completos.
  Future<void> reemplazar({
    required List<Almacen> almacenes,
    required List<Campana> campanas,
    required List<MaterialTextil> materiales,
    required List<Operario> operarios,
    required String timestampServidor,
  }) async {
    await _db.transaction((txn) async {
      for (final t in ['almacenes', 'campanas', 'materiales', 'operarios']) {
        await txn.delete(t);
      }
      final b = txn.batch();
      for (final a in almacenes) {
        b.insert('almacenes', a.toDb());
      }
      for (final c in campanas) {
        b.insert('campanas', c.toDb());
      }
      for (final m in materiales) {
        b.insert('materiales', m.toDb());
      }
      for (final o in operarios) {
        b.insert('operarios', o.toDb());
      }
      b.insert(
        'meta',
        {'clave': 'ultima_descarga', 'valor': timestampServidor},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await b.commit(noResult: true);
    });
  }

  Future<List<Almacen>> almacenes() async => (await _db.query(
        'almacenes',
        orderBy: 'razon_social COLLATE NOCASE, nombre_local COLLATE NOCASE',
      ))
          .map(Almacen.fromDb)
          .toList();

  Future<List<Campana>> campanas() async =>
      (await _db.query('campanas', orderBy: 'fecha_inicio DESC'))
          .map(Campana.fromDb)
          .toList();

  Future<List<Operario>> operarios() async =>
      (await _db.query('operarios', orderBy: 'nombre_completo COLLATE NOCASE'))
          .map(Operario.fromDb)
          .toList();

  /// Búsqueda por código, número de kardex o descripción.
  Future<List<MaterialTextil>> buscarMateriales(String texto, {int limite = 40}) async {
    final q = texto.trim();
    final filas = q.isEmpty
        ? await _db.query('materiales',
            orderBy: 'descripcion COLLATE NOCASE', limit: limite)
        : await _db.query(
            'materiales',
            where: 'codigo_material LIKE ? OR kardex_numero LIKE ? OR descripcion LIKE ?',
            // Los dos últimos argumentos son para los `?` del ORDER BY.
            whereArgs: ['%$q%', '%$q%', '%$q%', q, q],
            // Primero las coincidencias exactas de código o kardex.
            orderBy: 'CASE WHEN codigo_material = ? OR kardex_numero = ? THEN 0 ELSE 1 END, '
                'descripcion COLLATE NOCASE',
            limit: limite,
          );
    return filas.map(MaterialTextil.fromDb).toList();
  }

  Future<Map<String, int>> conteos() async {
    Future<int> contar(String t) async =>
        Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $t')) ?? 0;
    return {
      'almacenes': await contar('almacenes'),
      'campanas': await contar('campanas'),
      'materiales': await contar('materiales'),
      'operarios': await contar('operarios'),
    };
  }

  Future<String?> meta(String clave) async {
    final r = await _db.query('meta', where: 'clave = ?', whereArgs: [clave], limit: 1);
    return r.isEmpty ? null : r.first['valor'] as String?;
  }

  Future<void> guardarMeta(String clave, String? valor) => _db.insert(
        'meta',
        {'clave': clave, 'valor': valor},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}

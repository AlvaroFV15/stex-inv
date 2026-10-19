import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/formato.dart';
import '../../domain/models.dart';

class ReglaNegocioException implements Exception {
  ReglaNegocioException(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// Libros de conteo y sus movimientos, guardados solo en el dispositivo
/// hasta que se envían.
class LibrosRepository {
  LibrosRepository(this._db);
  final Database _db;
  static const _uuid = Uuid();

  static const _selectLibros = '''
    SELECT l.*,
           COUNT(m.movimiento_id) AS total_items,
           COALESCE(SUM(m.peso_neto), 0) AS peso_total
      FROM libros l
      LEFT JOIN movimientos m ON m.libro_id = l.libro_id''';

  Future<List<Libro>> _consultar(String where, List<Object?> args,
      {String orden = 'l.fecha_creacion DESC'}) async {
    final filas = await _db.rawQuery(
      '$_selectLibros ${where.isEmpty ? '' : 'WHERE $where'} '
      'GROUP BY l.libro_id ORDER BY $orden',
      args,
    );
    return filas.map(Libro.fromDb).toList();
  }

  Future<List<Libro>> todos() => _consultar('', const []);

  Future<Libro?> porId(String libroId) async {
    final r = await _consultar('l.libro_id = ?', [libroId]);
    return r.isEmpty ? null : r.first;
  }

  /// Solo puede haber un libro abierto por almacén en el dispositivo.
  Future<Libro?> abiertoDe(String almacenId) async {
    final r = await _consultar(
        'l.almacen_id = ? AND l.estado = ?', [almacenId, EstadoLibro.abierto.db]);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Libro>> pendientesDeEnvio() => _consultar(
        'l.estado = ?',
        [EstadoLibro.pendienteEnvio.db],
        orden: 'l.fecha_cierre ASC',
      );

  Future<int> contarPendientes() async =>
      Sqflite.firstIntValue(await _db.rawQuery(
        'SELECT COUNT(*) FROM libros WHERE estado = ?',
        [EstadoLibro.pendienteEnvio.db],
      )) ??
      0;

  /// Libros que todavía no llegaron al servidor (abiertos o pendientes).
  Future<int> contarSinEnviar() async =>
      Sqflite.firstIntValue(await _db.rawQuery(
        'SELECT COUNT(*) FROM libros WHERE estado <> ?',
        [EstadoLibro.enviado.db],
      )) ??
      0;

  Future<Libro> crear({
    required Campana campana,
    required Almacen almacen,
    required Operario operario,
  }) async {
    final id = _uuid.v4();
    await _db.transaction((txn) async {
      final yaAbierto = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM libros WHERE almacen_id = ? AND estado = ?',
            [almacen.id, EstadoLibro.abierto.db],
          )) ??
          0;
      if (yaAbierto > 0) {
        throw ReglaNegocioException('Ya hay un libro abierto para este almacén.');
      }
      await txn.insert('libros', {
        'libro_id': id,
        'campana_id': campana.id,
        'campana_nombre': campana.nombre,
        'almacen_id': almacen.id,
        'almacen_nombre': almacen.nombre,
        'operario_id': operario.id,
        'operario_nombre': operario.nombre,
        'fecha_creacion': ahoraIso(),
        'estado': EstadoLibro.abierto.db,
      });
    });
    return (await porId(id))!;
  }

  Future<List<Movimiento>> movimientos(String libroId) async => (await _db.query(
        'movimientos',
        where: 'libro_id = ?',
        whereArgs: [libroId],
        orderBy: 'fecha_registro DESC',
      ))
          .map(Movimiento.fromDb)
          .toList();

  /// Guarda un conteo. La transacción hace que el registro quede escrito en
  /// disco (WAL + synchronous FULL) antes de devolver el control a la UI.
  Future<void> agregarMovimiento({
    required String libroId,
    required MaterialTextil material,
    required int cantidad,
    required double peso,
    required String? observacion,
    required String operarioId,
  }) async {
    await _db.transaction((txn) async {
      final estado = await txn.query('libros',
          columns: ['estado'], where: 'libro_id = ?', whereArgs: [libroId]);
      if (estado.isEmpty || estado.first['estado'] != EstadoLibro.abierto.db) {
        throw ReglaNegocioException('El libro ya no está abierto.');
      }
      await txn.insert('movimientos', {
        'movimiento_id': _uuid.v4(),
        'libro_id': libroId,
        'material_id': material.id,
        'material_codigo': material.codigo,
        'material_descripcion': material.descripcion,
        'cantidad_unidad': cantidad,
        'peso_neto': peso,
        'observacion': (observacion == null || observacion.trim().isEmpty)
            ? null
            : observacion.trim(),
        'fecha_registro': ahoraIso(),
        'operario_id': operarioId,
      });
    });
  }

  Future<void> eliminarMovimiento(Movimiento m) async {
    await _db.transaction((txn) async {
      final estado = await txn.query('libros',
          columns: ['estado'], where: 'libro_id = ?', whereArgs: [m.libroId]);
      if (estado.isEmpty || estado.first['estado'] != EstadoLibro.abierto.db) {
        throw ReglaNegocioException('Solo se pueden borrar registros de un libro abierto.');
      }
      await txn.delete('movimientos', where: 'movimiento_id = ?', whereArgs: [m.id]);
    });
  }

  /// Cierra el libro y lo deja en cola para enviarse.
  Future<void> cerrar(String libroId) async {
    await _db.transaction((txn) async {
      final items = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM movimientos WHERE libro_id = ?', [libroId])) ??
          0;
      if (items == 0) {
        throw ReglaNegocioException('No se puede cerrar un libro sin registros.');
      }
      await txn.update(
        'libros',
        {
          'estado': EstadoLibro.pendienteEnvio.db,
          'fecha_cierre': ahoraIso(),
          'ultimo_error': null,
        },
        where: 'libro_id = ? AND estado = ?',
        whereArgs: [libroId, EstadoLibro.abierto.db],
      );
    });
  }

  /// Devuelve un libro pendiente al estado abierto para corregirlo,
  /// siempre que no se haya enviado y el almacén no tenga otro abierto.
  Future<void> reabrir(Libro libro) async {
    await _db.transaction((txn) async {
      final otro = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM libros WHERE almacen_id = ? AND estado = ? AND libro_id <> ?',
            [libro.almacenId, EstadoLibro.abierto.db, libro.id],
          )) ??
          0;
      if (otro > 0) {
        throw ReglaNegocioException(
            'Ese almacén ya tiene otro libro abierto. Ciérralo primero.');
      }
      final n = await txn.update(
        'libros',
        {'estado': EstadoLibro.abierto.db, 'fecha_cierre': null},
        where: 'libro_id = ? AND estado = ?',
        whereArgs: [libro.id, EstadoLibro.pendienteEnvio.db],
      );
      if (n == 0) {
        throw ReglaNegocioException('El libro ya fue enviado y no se puede reabrir.');
      }
    });
  }

  /// Descarta un libro abierto que no tiene registros.
  Future<void> descartarVacio(String libroId) async {
    await _db.transaction((txn) async {
      final items = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM movimientos WHERE libro_id = ?', [libroId])) ??
          0;
      if (items > 0) {
        throw ReglaNegocioException('El libro tiene registros; ciérralo o bórralos primero.');
      }
      await txn.delete('libros',
          where: 'libro_id = ? AND estado = ?',
          whereArgs: [libroId, EstadoLibro.abierto.db]);
    });
  }

  Future<void> marcarEnviado(String libroId) => _db.update(
        'libros',
        {
          'estado': EstadoLibro.enviado.db,
          'fecha_envio': ahoraIso(),
          'ultimo_error': null,
        },
        where: 'libro_id = ?',
        whereArgs: [libroId],
      );

  Future<void> registrarFallo(String libroId, String error) => _db.rawUpdate(
        'UPDATE libros SET intentos_sync = intentos_sync + 1, ultimo_error = ? '
        'WHERE libro_id = ?',
        [error, libroId],
      );

  /// Borra del dispositivo los libros enviados hace más de [dias] días.
  Future<int> purgarEnviados(int dias) {
    final limite =
        DateTime.now().toUtc().subtract(Duration(days: dias)).toIso8601String();
    return _db.delete(
      'libros',
      where: 'estado = ? AND fecha_envio < ?',
      whereArgs: [EstadoLibro.enviado.db, limite],
    );
  }
}

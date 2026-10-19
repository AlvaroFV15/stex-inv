import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Base de datos local.
///
/// En el dispositivo se abre cifrada (SQLCipher, AES-256) y en modo WAL con
/// [abrirCifrada]. En las pruebas se crea en memoria con sqflite_common_ffi
/// usando el mismo [crearEsquema].
///
/// Sobre `synchronous`: la especificación v3 proponía NORMAL, pero en modo
/// WAL con NORMAL un apagón puede revertir las últimas transacciones ya
/// confirmadas (la base queda íntegra, pero los últimos conteos se pierden).
/// HU-07 exige que el 100 % de los registros sobreviva a un apagado repentino,
/// así que se usa FULL. Para capturas manuales el costo es imperceptible.
class AppDatabase {
  AppDatabase(this.db);

  final Database db;

  static const archivo = 'stex_inv.db';
  static const version = 1;

  static Future<String> _rutaArchivo() async =>
      p.join(await getDatabasesPath(), archivo);

  /// Abre (o crea) la base cifrada del dispositivo.
  static Future<AppDatabase> abrirCifrada(String clave) async {
    final db = await openDatabase(
      await _rutaArchivo(),
      password: clave,
      version: version,
      onConfigure: (db) async {
        // journal_mode devuelve una fila, por eso rawQuery y no execute.
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.rawQuery('PRAGMA synchronous = FULL');
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) => crearEsquema(db),
    );
    return AppDatabase(db);
  }

  /// Borra el archivo cifrado (desvincular dispositivo).
  static Future<void> eliminarCifrada() async =>
      deleteDatabase(await _rutaArchivo());

  Future<void> cerrar() => db.close();

  static Future<void> crearEsquema(Database db) async {
    final b = db.batch();
    b.execute('''
      CREATE TABLE meta (
        clave TEXT PRIMARY KEY,
        valor TEXT
      )''');
    b.execute('''
      CREATE TABLE almacenes (
        almacen_id TEXT PRIMARY KEY,
        codigo_almacen TEXT,
        nro_almacen TEXT,
        razon_social TEXT,
        nombre_local TEXT
      )''');
    b.execute('''
      CREATE TABLE campanas (
        campana_id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        fecha_inicio TEXT,
        fecha_fin TEXT
      )''');
    b.execute('''
      CREATE TABLE materiales (
        material_id TEXT PRIMARY KEY,
        codigo_material TEXT,
        kardex_numero TEXT,
        descripcion TEXT NOT NULL,
        tipo TEXT
      )''');
    b.execute('''
      CREATE TABLE operarios (
        operario_id TEXT PRIMARY KEY,
        nombre_completo TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        almacen_id TEXT
      )''');
    // Los libros copian los nombres de campaña, almacén y operario para que
    // sigan mostrándose bien aunque esos maestros cambien en una descarga.
    b.execute('''
      CREATE TABLE libros (
        libro_id TEXT PRIMARY KEY,
        campana_id TEXT NOT NULL,
        campana_nombre TEXT NOT NULL,
        almacen_id TEXT NOT NULL,
        almacen_nombre TEXT NOT NULL,
        operario_id TEXT NOT NULL,
        operario_nombre TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        fecha_cierre TEXT,
        fecha_envio TEXT,
        estado TEXT NOT NULL DEFAULT 'ABIERTO',
        intentos_sync INTEGER NOT NULL DEFAULT 0,
        ultimo_error TEXT
      )''');
    b.execute('CREATE INDEX idx_libros_estado ON libros(estado)');
    b.execute('''
      CREATE TABLE movimientos (
        movimiento_id TEXT PRIMARY KEY,
        libro_id TEXT NOT NULL REFERENCES libros(libro_id) ON DELETE CASCADE,
        material_id TEXT NOT NULL,
        material_codigo TEXT,
        material_descripcion TEXT NOT NULL,
        cantidad_unidad INTEGER NOT NULL CHECK (cantidad_unidad >= 0),
        peso_neto REAL NOT NULL CHECK (peso_neto >= 0),
        observacion TEXT,
        fecha_registro TEXT NOT NULL,
        operario_id TEXT NOT NULL
      )''');
    b.execute('CREATE INDEX idx_movimientos_libro ON movimientos(libro_id)');
    await b.commit(noResult: true);
  }
}

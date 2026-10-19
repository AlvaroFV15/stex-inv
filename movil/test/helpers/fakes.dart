import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stex_inv_movil/core/pin_hash.dart';
import 'package:stex_inv_movil/data/local/database.dart';
import 'package:stex_inv_movil/data/local/secure_store.dart';
import 'package:stex_inv_movil/data/remote/api_client.dart';
import 'package:stex_inv_movil/data/remote/auth_service.dart';
import 'package:stex_inv_movil/state/app_state.dart';
import 'package:stex_inv_movil/state/conectividad.dart';

/// Dobles de prueba compartidos por las pruebas unitarias y de widgets.
/// Los IDs coinciden con la semilla del servidor local (backend/db/03_semilla.sql).

const idAlmacen1 = 'a1000000-0000-4000-8000-000000000001';
const idAlmacen2 = 'a1000000-0000-4000-8000-000000000002';
const idCampana = 'c1000000-0000-4000-8000-000000000001';
const idCampana2 = 'c1000000-0000-4000-8000-000000000009';
const idHilo = 'b1000000-0000-4000-8000-000000000001';
const idJersey = 'b1000000-0000-4000-8000-000000000002';
const idJuan = 'd1000000-0000-4000-8000-000000000001';
const idMaria = 'd1000000-0000-4000-8000-000000000002';
const correo = 'almacen1@apjltextil.com';
const password = 'Stex2026!';

/// Respuesta de GET /api/sync/download como la del servidor.
Map<String, dynamic> maestrosDeEjemplo({bool dosCampanas = false, bool dosAlmacenes = false}) => {
      'success': true,
      'data': {
        'campanas': [
          {
            'campana_id': idCampana,
            'nombre': 'Inventario Octubre 2026',
            'fecha_inicio': '2026-10-01',
            'fecha_fin': '2026-10-31',
          },
          if (dosCampanas)
            {
              'campana_id': idCampana2,
              'nombre': 'Inventario Extra',
              'fecha_inicio': '2026-10-15',
              'fecha_fin': '2026-10-20',
            },
        ],
        'almacenes': [
          {
            'almacen_id': idAlmacen1,
            'codigo_almacen': 'TEJ04',
            'nro_almacen': '9',
            'razon_social': 'Textiles del Norte S.A.C.',
            'nombre_local': 'Planta Tejeduría',
          },
          if (dosAlmacenes)
            {
              'almacen_id': idAlmacen2,
              'codigo_almacen': 'CAN01',
              'nro_almacen': '3',
              'razon_social': 'APJL TEXTIL S.A.C.',
              'nombre_local': 'Sede Principal Cañete',
            },
        ],
        'materiales': [
          {
            'material_id': idHilo,
            'codigo_material': 'MAT-001',
            'kardex_numero': '1001',
            'descripcion': 'Hilo Algodón 30/1 Peinado',
          },
          {
            'material_id': idJersey,
            'codigo_material': 'MAT-014',
            'kardex_numero': '1014',
            'descripcion': 'Crudo jersey 24/1',
          },
        ],
        'operarios': [
          {
            'operario_id': idJuan,
            'nombre_completo': 'Juan Carlos Pérez',
            'almacen_id': idAlmacen1,
            'pin_hash': hashPin(idJuan, '1234'),
          },
          {
            'operario_id': idMaria,
            'nombre_completo': 'María Torres',
            'almacen_id': idAlmacen1,
            'pin_hash': hashPin(idMaria, '4321'),
          },
        ],
      },
      'timestamp': '2026-10-19T12:00:00.000Z',
    };

class ConectividadFalsa extends Conectividad {
  ConectividadFalsa([this._online = true]);
  bool _online;

  @override
  bool get online => _online;

  set online(bool valor) {
    if (valor == _online) return;
    _online = valor;
    notifyListeners();
  }
}

class AuthFalso implements ServicioAuth {
  AuthFalso({Map<String, String>? cuentas}) : cuentas = cuentas ?? {correo: password};

  final Map<String, String> cuentas;
  String? token;
  int renovaciones = 0;
  int cierres = 0;

  /// La renovación responde "sesión inválida" (refresh token revocado).
  bool renovacionInvalida = false;

  /// La renovación falla por red.
  bool renovacionSinRed = false;

  @override
  Future<void> iniciarSesion(String email, String pass) async {
    if (cuentas[email.trim()] != pass) {
      throw ApiException('Correo o contraseña incorrectos.');
    }
    token = 'token-1';
  }

  @override
  Future<String?> tokenVigente({bool forzarRenovacion = false}) async {
    if (token == null) return null;
    if (forzarRenovacion) {
      if (renovacionSinRed) throw const SinConexionAuth();
      if (renovacionInvalida) return null;
      renovaciones++;
      token = 'token-${renovaciones + 1}';
    }
    return token;
  }

  @override
  Future<void> cerrarSesion() async {
    token = null;
    cierres++;
  }
}

class ApiFalsa implements SyncApi {
  Map<String, dynamic> maestros = maestrosDeEjemplo();
  ApiException? errorDescarga;

  /// Permite fallar un envío según su cuerpo. Devuelve null para aceptarlo.
  ApiException? Function(Map<String, Object?> cuerpo)? errorSubida;

  final List<Map<String, Object?>> subidos = [];
  final Set<String> librosEnServidor = {};
  int descargas = 0;
  int intentosSubida = 0;

  @override
  Future<Map<String, dynamic>> descargarMaestros() async {
    descargas++;
    final e = errorDescarga;
    if (e != null) throw e;
    // Copia profunda: la app no debe poder modificar el original.
    return jsonDecode(jsonEncode(maestros)) as Map<String, dynamic>;
  }

  @override
  Future<ResultadoSubida> subirLibro(Map<String, Object?> cuerpo) async {
    intentosSubida++;
    final e = errorSubida?.call(cuerpo);
    if (e != null) throw e;
    final copia = jsonDecode(jsonEncode(cuerpo)) as Map<String, Object?>;
    subidos.add(copia);
    final id = cuerpo['libro_id'] as String;
    final duplicado = !librosEnServidor.add(id);
    return ResultadoSubida(libroId: id, duplicado: duplicado);
  }
}

class AlmacenSeguroFalso implements AlmacenSeguro {
  String? clave;
  String? email;
  int borrados = 0;

  @override
  Future<String> claveBaseDatos() async => clave ??= SecureStore.generarClave();

  @override
  Future<String?> emailVinculado() async => email;

  @override
  Future<void> guardarEmailVinculado(String e) async => email = e;

  @override
  Future<void> borrarTodo() async {
    clave = null;
    email = null;
    borrados++;
  }
}

Future<Database> _abrir(String ruta) {
  sqfliteFfiInit();
  return databaseFactoryFfiNoIsolate.openDatabase(
    ruta,
    options: OpenDatabaseOptions(
      version: AppDatabase.version,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => AppDatabase.crearEsquema(db),
    ),
  );
}

/// Base nueva en memoria, con el mismo esquema que el dispositivo.
Future<AppDatabase> abrirBaseEnMemoria([String _ = '']) async =>
    AppDatabase(await _abrir(inMemoryDatabasePath));

/// Base en un archivo temporal: sobrevive a cerrar y reabrir (simula
/// reiniciar la app o un apagado del equipo).
class BaseEnArchivo {
  BaseEnArchivo() : ruta = '${Directory.systemTemp.createTempSync('stex_test_').path}/stex.db';

  final String ruta;
  int eliminaciones = 0;

  Future<AppDatabase> abrir([String _ = '']) async => AppDatabase(await _abrir(ruta));

  Future<void> eliminar() async {
    eliminaciones++;
    await databaseFactoryFfiNoIsolate.deleteDatabase(ruta);
  }
}

/// Todo lo necesario para construir un AppState de prueba.
class Banco {
  Banco({bool online = true, BaseEnArchivo? base, this.configCompleta = true})
      : red = ConectividadFalsa(online),
        base = base ?? BaseEnArchivo();

  final ConectividadFalsa red;
  final AuthFalso auth = AuthFalso();
  final ApiFalsa api = ApiFalsa();
  final AlmacenSeguroFalso seguro = AlmacenSeguroFalso();
  final BaseEnArchivo base;
  final bool configCompleta;
  DateTime reloj = DateTime(2026, 10, 19, 8);

  AppState crearApp({bool esperarFrameReal = false}) => AppState(
        conectividad: red,
        auth: auth,
        api: api,
        seguro: seguro,
        abrirBase: base.abrir,
        eliminarBase: base.eliminar,
        configCompleta: configCompleta,
        ahora: () => reloj,
        esperarFrame: esperarFrameReal ? null : () async {},
        intervaloSync: const Duration(hours: 1),
        retardoReconexion: Duration.zero,
      );
}

/// Espera (en tiempo real) a que se cumpla una condición. Para pruebas sin
/// FakeAsync (las unitarias); en pruebas de widgets usar `pumpHasta`.
Future<void> esperarHasta(bool Function() condicion,
    {Duration limite = const Duration(seconds: 5)}) async {
  final fin = DateTime.now().add(limite);
  while (!condicion()) {
    if (DateTime.now().isAfter(fin)) {
      throw StateError('La condición no se cumplió en $limite');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

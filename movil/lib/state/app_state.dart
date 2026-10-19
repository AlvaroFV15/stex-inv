import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/config.dart';
import '../core/pin_hash.dart';
import '../data/local/database.dart';
import '../data/local/secure_store.dart';
import '../data/remote/api_client.dart';
import '../data/remote/auth_service.dart';
import '../data/repositories/libros_repository.dart';
import '../data/repositories/maestros_repository.dart';
import '../domain/models.dart';
import 'conectividad.dart';
import 'sync_controller.dart';

enum Fase { cargando, configFaltante, errorBaseLocal, sinVincular, sinOperario, listo }

class ResultadoPin {
  const ResultadoPin(this.ok, [this.mensaje]);
  final bool ok;
  final String? mensaje;
}

/// Estado global: vinculación del dispositivo, operario en turno y almacén
/// seleccionado. Expone los repositorios y el controlador de sincronización.
///
/// Todas las dependencias se inyectan para poder probarlo sin dispositivo:
/// en las pruebas se usa una base en memoria y servicios falsos.
class AppState extends ChangeNotifier {
  AppState({
    required this.conectividad,
    required this.auth,
    required this.api,
    required this.seguro,
    required this.abrirBase,
    required this.eliminarBase,
    this.configCompleta = true,
    this.ahora = DateTime.now,
    Future<void> Function()? esperarFrame,
    this.intervaloSync = const Duration(minutes: 5),
    this.retardoReconexion = const Duration(seconds: 3),
  }) : _esperarFrame = esperarFrame ?? (() => SchedulerBinding.instance.endOfFrame);

  final Conectividad conectividad;
  final ServicioAuth auth;
  final SyncApi api;
  final AlmacenSeguro seguro;
  final Future<AppDatabase> Function(String clave) abrirBase;
  final Future<void> Function() eliminarBase;
  final bool configCompleta;
  final DateTime Function() ahora;
  final Future<void> Function() _esperarFrame;
  final Duration intervaloSync;
  final Duration retardoReconexion;

  AppDatabase? _db;
  MaestrosRepository? _maestros;
  LibrosRepository? _libros;
  SyncController? _sync;

  MaestrosRepository get maestros => _maestros!;
  LibrosRepository get libros => _libros!;
  SyncController get sync => _sync!;

  Fase fase = Fase.cargando;
  String? detalleError;
  String? emailVinculado;
  Operario? operario;
  List<Almacen> almacenes = const [];
  String? almacenId;
  String? almacenFavoritoId;

  /// Cambia cada vez que se modifican libros o termina un envío; las
  /// pantallas la usan para saber cuándo volver a leer la base local.
  int revisionLibros = 0;

  final Map<String, int> _fallosPin = {};
  final Map<String, DateTime> _bloqueadoHasta = {};

  Almacen? get almacenActual {
    for (final a in almacenes) {
      if (a.id == almacenId) return a;
    }
    return null;
  }

  // ---------------------------------------------------------------- arranque

  Future<void> iniciar() async {
    fase = Fase.cargando;
    notifyListeners();

    if (!configCompleta) {
      fase = Fase.configFaltante;
      notifyListeners();
      return;
    }

    try {
      _db = await abrirBase(await seguro.claveBaseDatos());
    } catch (e) {
      // Suele pasar si la clave del Keystore/Keychain se perdió pero el
      // archivo de la base sigue ahí (restauración de copia de seguridad).
      detalleError = e.toString();
      fase = Fase.errorBaseLocal;
      notifyListeners();
      return;
    }

    _maestros = MaestrosRepository(_db!.db);
    _libros = LibrosRepository(_db!.db);
    _sync = SyncController(
      libros: libros,
      maestros: maestros,
      api: api,
      conectividad: conectividad,
      intervalo: intervaloSync,
      retardoReconexion: retardoReconexion,
    )..addListener(_alCambiarSync);

    await libros.purgarEnviados(AppConfig.diasRetencionEnviados);
    await sync.refrescarPendientes();

    emailVinculado = await seguro.emailVinculado();
    final vinculadoEnBase = await maestros.meta('vinculado') == '1';
    if (emailVinculado == null || !vinculadoEnBase) {
      fase = Fase.sinVincular;
    } else {
      await _cargarAlmacenes();
      fase = Fase.sinOperario;
      // Si hay red, intenta enviar lo que quedó pendiente de la última vez.
      sync.enviarPendientes(automatico: true);
    }
    notifyListeners();
  }

  /// Borra la base local ilegible y vuelve a empezar. Se pierden los datos
  /// que no se enviaron; solo se ofrece desde la pantalla de error.
  Future<void> reiniciarBaseLocal() async {
    await _cerrarTodo();
    await eliminarBase();
    await auth.cerrarSesion();
    await seguro.borrarTodo();
    await iniciar();
  }

  void _alCambiarSync() {
    revisionLibros++;
    notifyListeners();
  }

  /// Cierra la base y el controlador de sincronización. Primero pasa a la
  /// pantalla de carga y espera un frame, para que ninguna pantalla siga
  /// leyendo de la base mientras se cierra.
  Future<void> _cerrarTodo() async {
    fase = Fase.cargando;
    notifyListeners();
    await _esperarFrame();
    final sync = _sync;
    _sync = null;
    sync?.removeListener(_alCambiarSync);
    sync?.dispose();
    await _db?.cerrar();
    _db = null;
  }

  /// Libera recursos (temporizadores y base). Usado al cerrar la app y en pruebas.
  Future<void> liberar() async {
    final sync = _sync;
    _sync = null;
    sync?.removeListener(_alCambiarSync);
    sync?.dispose();
    await _db?.cerrar();
    _db = null;
  }

  // -------------------------------------------------------------- vinculación

  /// Paso 1 + 2 de la especificación: login de la cuenta del almacén y
  /// descarga inicial de maestros. Se hace una sola vez por dispositivo.
  Future<void> vincular(String email, String password) async {
    if (!conectividad.online) {
      throw ApiException('Necesitas conexión a internet para vincular el dispositivo.',
          sinConexion: true);
    }
    await auth.iniciarSesion(email, password);
    try {
      await sync.descargarMaestros();
    } catch (_) {
      await auth.cerrarSesion();
      rethrow;
    }
    await seguro.guardarEmailVinculado(email.trim());
    await maestros.guardarMeta('vinculado', '1');
    emailVinculado = email.trim();
    await _cargarAlmacenes();
    fase = Fase.sinOperario;
    notifyListeners();
  }

  /// Cuando la sesión expiró: vuelve a autenticar la misma cuenta sin tocar
  /// los datos locales.
  Future<void> reautenticar(String password) async {
    final email = emailVinculado;
    if (email == null) return;
    await auth.iniciarSesion(email, password);
    sync.sesionInvalida = false;
    notifyListeners();
    await sync.enviarPendientes();
  }

  /// Desvincula el dispositivo: borra la base local, la sesión y las claves.
  Future<void> desvincular() async {
    await _cerrarTodo();
    await eliminarBase();
    await auth.cerrarSesion();
    await seguro.borrarTodo();
    operario = null;
    emailVinculado = null;
    almacenes = const [];
    almacenId = null;
    almacenFavoritoId = null;
    _fallosPin.clear();
    _bloqueadoHasta.clear();
    await iniciar();
  }

  // ------------------------------------------------------------ datos maestros

  Future<void> _cargarAlmacenes() async {
    almacenes = await maestros.almacenes();
    almacenFavoritoId = await maestros.meta('almacen_favorito');
    if (almacenes.every((a) => a.id != almacenId)) {
      almacenId = _almacenInicial();
    }
  }

  String? _almacenInicial() {
    bool existe(String? id) => id != null && almacenes.any((a) => a.id == id);
    if (existe(almacenFavoritoId)) return almacenFavoritoId;
    if (existe(operario?.almacenId)) return operario!.almacenId;
    return almacenes.isEmpty ? null : almacenes.first.id;
  }

  Future<void> actualizarMaestros() async {
    await sync.descargarMaestros();
    await _cargarAlmacenes();
    notifyListeners();
  }

  // ------------------------------------------------------------ operario / PIN

  Duration? bloqueoRestante(Operario o) {
    final hasta = _bloqueadoHasta[o.id];
    if (hasta == null) return null;
    final resta = hasta.difference(ahora());
    return resta.isNegative || resta == Duration.zero ? null : resta;
  }

  /// Validación 100 % offline contra el hash guardado en el dispositivo.
  ResultadoPin ingresar(Operario o, String pin) {
    final bloqueo = bloqueoRestante(o);
    if (bloqueo != null) {
      return ResultadoPin(false, 'Demasiados intentos. Espera ${bloqueo.inSeconds + 1} s.');
    }
    if (hashPin(o.id, pin) != o.pinHash) {
      final fallos = (_fallosPin[o.id] ?? 0) + 1;
      if (fallos >= AppConfig.maxIntentosPin) {
        _fallosPin.remove(o.id);
        _bloqueadoHasta[o.id] = ahora().add(AppConfig.bloqueoPin);
        return ResultadoPin(false,
            'PIN incorrecto. Bloqueado por ${AppConfig.bloqueoPin.inSeconds} s.');
      }
      _fallosPin[o.id] = fallos;
      return ResultadoPin(
          false, 'PIN incorrecto. Te quedan ${AppConfig.maxIntentosPin - fallos} intentos.');
    }
    _fallosPin.remove(o.id);
    _bloqueadoHasta.remove(o.id);
    operario = o;
    almacenId = _almacenInicial();
    fase = Fase.listo;
    notifyListeners();
    return const ResultadoPin(true);
  }

  void cerrarTurno() {
    operario = null;
    fase = Fase.sinOperario;
    notifyListeners();
  }

  // ------------------------------------------------------------------ almacén

  void seleccionarAlmacen(String id) {
    almacenId = id;
    notifyListeners();
  }

  Future<void> alternarFavorito() async {
    final id = almacenId;
    if (id == null) return;
    almacenFavoritoId = almacenFavoritoId == id ? null : id;
    await maestros.guardarMeta('almacen_favorito', almacenFavoritoId);
    notifyListeners();
  }

  /// Avisa a la UI que cambiaron libros o movimientos.
  Future<void> librosCambiaron() async {
    revisionLibros++;
    await sync.refrescarPendientes(); // también notifica a los oyentes
  }
}

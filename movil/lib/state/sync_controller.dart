import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/pin_hash.dart';
import '../data/remote/api_client.dart';
import '../data/repositories/libros_repository.dart';
import '../data/repositories/maestros_repository.dart';
import '../domain/models.dart';
import 'conectividad.dart';

class ResultadoEnvio {
  const ResultadoEnvio({this.enviados = 0, this.duplicados = 0, this.fallidos = 0, this.mensaje});
  final int enviados;

  /// Libros que el servidor ya tenía (cuentan también como enviados).
  final int duplicados;
  final int fallidos;
  final String? mensaje;
}

/// Envía los libros cerrados al servidor y baja los datos maestros.
///
/// Envío automático: al recuperar la red, al volver la app a primer plano,
/// cada [intervalo] si hay pendientes, y manualmente desde la pestaña Sync.
/// Cada libro se envía con su `libro_id` generado en el dispositivo, así que
/// reenviar uno que el servidor ya guardó no crea un duplicado.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.libros,
    required this.maestros,
    required this.api,
    required this.conectividad,
    this.intervalo = const Duration(minutes: 5),
    this.retardoReconexion = const Duration(seconds: 3),
  }) {
    _estabaOnline = conectividad.online;
    conectividad.addListener(_alCambiarRed);
    _timer = Timer.periodic(intervalo, (_) {
      if (pendientes > 0) enviarPendientes(automatico: true);
    });
  }

  final LibrosRepository libros;
  final MaestrosRepository maestros;
  final SyncApi api;
  final Conectividad conectividad;
  final Duration intervalo;

  /// Espera tras recuperar la red: el Wi-Fi suele reportarse conectado
  /// antes de tener IP.
  final Duration retardoReconexion;

  Timer? _timer;
  bool _estabaOnline = false;
  bool _liberado = false;
  Future<ResultadoEnvio>? _envioEnCurso;

  bool get enviando => _envioEnCurso != null;
  bool descargando = false;
  int pendientes = 0;
  bool sesionInvalida = false;
  String? ultimoMensaje;
  bool ultimoFueError = false;
  DateTime? ultimoEnvioOk;

  void _avisar() {
    if (!_liberado) notifyListeners();
  }

  void _alCambiarRed() {
    final ahora = conectividad.online;
    if (ahora && !_estabaOnline) {
      Future<void>.delayed(retardoReconexion, () {
        if (!_liberado) enviarPendientes(automatico: true);
      });
    }
    _estabaOnline = ahora;
  }

  Future<void> refrescarPendientes() async {
    pendientes = await libros.contarPendientes();
    _avisar();
  }

  /// Envía la cola. Si ya hay un envío en curso, devuelve ese mismo.
  Future<ResultadoEnvio> enviarPendientes({bool automatico = false}) {
    final enCurso = _envioEnCurso;
    if (enCurso != null) return enCurso;
    final f = _enviarSeguro(automatico).whenComplete(() {
      _envioEnCurso = null;
      _avisar();
    });
    _envioEnCurso = f;
    _avisar();
    return f;
  }

  /// Nunca lanza: quien llama sin esperar (temporizador, reconexión) no
  /// debe provocar errores no controlados.
  Future<ResultadoEnvio> _enviarSeguro(bool automatico) async {
    try {
      return await _enviar(automatico);
    } catch (e) {
      ultimoMensaje = 'Error al enviar: $e';
      ultimoFueError = true;
      return ResultadoEnvio(mensaje: e.toString());
    }
  }

  Future<ResultadoEnvio> _enviar(bool automatico) async {
    if (sesionInvalida && automatico) return const ResultadoEnvio();
    if (!conectividad.online) {
      if (!automatico) {
        ultimoMensaje = 'Sin conexión. Los libros quedan guardados en el dispositivo.';
        ultimoFueError = true;
      }
      return const ResultadoEnvio(mensaje: 'Sin conexión.');
    }

    final cola = await libros.pendientesDeEnvio();
    if (cola.isEmpty) {
      await refrescarPendientes();
      return const ResultadoEnvio();
    }

    var ok = 0;
    var duplicados = 0;
    var fallidos = 0;
    String? mensaje;
    try {
      for (final libro in cola) {
        try {
          final movs = await libros.movimientos(libro.id);
          final r = await api.subirLibro(cuerpoDeEnvio(libro, movs));
          await libros.marcarEnviado(libro.id);
          ok++;
          if (r.duplicado) duplicados++;
        } on ApiException catch (e) {
          await libros.registrarFallo(libro.id, e.mensaje);
          fallidos++;
          mensaje = e.mensaje;
          if (e.sesionInvalida) {
            sesionInvalida = true;
            break;
          }
          // Si se cayó la red, no tiene sentido seguir con el resto.
          if (e.sinConexion) break;
        } catch (e) {
          await libros.registrarFallo(libro.id, e.toString());
          fallidos++;
          mensaje = e.toString();
        }
      }
      await libros.purgarEnviados(AppConfig.diasRetencionEnviados);
    } finally {
      pendientes = await libros.contarPendientes();
      if (ok > 0) ultimoEnvioOk = DateTime.now();
      if (fallidos > 0) {
        ultimoMensaje = mensaje;
        ultimoFueError = true;
      } else if (ok > 0) {
        ultimoMensaje = ok == 1 ? '1 libro enviado.' : '$ok libros enviados.';
        ultimoFueError = false;
      }
    }
    return ResultadoEnvio(enviados: ok, duplicados: duplicados, fallidos: fallidos, mensaje: mensaje);
  }

  /// Cuerpo de POST /api/sync/upload (contrato v2.1).
  static Map<String, Object?> cuerpoDeEnvio(Libro l, List<Movimiento> movs) => {
        'libro_id': l.id,
        'campana_id': l.campanaId,
        'almacen_id': l.almacenId,
        'operario_id': l.operarioId,
        'fecha_conteo': l.fechaCreacion.toUtc().toIso8601String(),
        'fecha_cierre': l.fechaCierre?.toUtc().toIso8601String(),
        // El repositorio devuelve los más recientes primero; se envían en
        // orden de captura.
        'detalles': movs.reversed.map((m) => m.toApi()).toList(),
      };

  /// Baja campañas, almacenes, materiales y operarios y los reemplaza en el
  /// dispositivo. Lanza [ApiException] si falla; los datos anteriores se
  /// conservan intactos en ese caso.
  Future<void> descargarMaestros() async {
    if (descargando) return;
    descargando = true;
    _avisar();
    try {
      final r = await api.descargarMaestros();
      final data = Map<String, dynamic>.from(r['data'] as Map);
      List<Map<String, dynamic>> lista(String k) => ((data[k] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final operarios = lista('operarios').map((j) {
        // Compatibilidad: si el servidor aún manda el PIN en claro, se
        // convierte a hash aquí y el PIN nunca se guarda en el dispositivo.
        if ((j['pin_hash'] ?? '').toString().isEmpty && j['pin_seguridad'] != null) {
          j['pin_hash'] = hashPin(j['operario_id'].toString(), j['pin_seguridad'].toString());
        }
        return Operario.fromJson(j);
      }).where((o) => o.id.isNotEmpty && o.pinHash.isNotEmpty).toList();

      await maestros.reemplazar(
        almacenes: lista('almacenes').map(Almacen.fromJson).toList(),
        campanas: lista('campanas').map(Campana.fromJson).toList(),
        materiales: lista('materiales').map(MaterialTextil.fromJson).toList(),
        operarios: operarios,
        timestampServidor:
            (r['timestamp'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
      );
      sesionInvalida = false;
    } on ApiException catch (e) {
      if (e.sesionInvalida) sesionInvalida = true;
      rethrow;
    } finally {
      descargando = false;
      _avisar();
    }
  }

  @override
  void dispose() {
    _liberado = true;
    _timer?.cancel();
    conectividad.removeListener(_alCambiarRed);
    super.dispose();
  }
}

/// Modelos de la app. Cada uno sabe leerse del JSON del servidor
/// (`fromJson`) y de/hacia una fila de SQLite (`fromDb` / `toDb`).
library;

String _s(Map<String, dynamic> m, String clave, [String? alterna]) {
  final v = m[clave] ?? (alterna == null ? null : m[alterna]);
  return v == null ? '' : v.toString();
}

class Almacen {
  const Almacen({
    required this.id,
    required this.codigo,
    required this.nro,
    required this.razonSocial,
    required this.nombreLocal,
  });

  final String id;
  final String codigo;
  final String nro;
  final String razonSocial;
  final String nombreLocal;

  /// Texto principal que se muestra en el selector y la cabecera.
  String get nombre => razonSocial.isNotEmpty ? razonSocial : nombreLocal;

  /// Línea secundaria: "Alm. 9 · Sede Principal Cañete".
  String get detalle => [
        if (nro.isNotEmpty) 'Alm. $nro',
        if (nombreLocal.isNotEmpty && nombreLocal != nombre) nombreLocal,
      ].join(' · ');

  factory Almacen.fromJson(Map<String, dynamic> j) => Almacen(
        id: _s(j, 'almacen_id'),
        codigo: _s(j, 'codigo_almacen'),
        nro: _s(j, 'nro_almacen'),
        razonSocial: _s(j, 'razon_social'),
        nombreLocal: _s(j, 'nombre_local'),
      );

  factory Almacen.fromDb(Map<String, Object?> r) =>
      Almacen.fromJson(Map<String, dynamic>.from(r));

  Map<String, Object?> toDb() => {
        'almacen_id': id,
        'codigo_almacen': codigo,
        'nro_almacen': nro,
        'razon_social': razonSocial,
        'nombre_local': nombreLocal,
      };
}

class Campana {
  const Campana({
    required this.id,
    required this.nombre,
    required this.fechaInicio,
    required this.fechaFin,
  });

  final String id;
  final String nombre;
  final String fechaInicio;
  final String fechaFin;

  factory Campana.fromJson(Map<String, dynamic> j) => Campana(
        // El panel usa `campanas_id` como nombre de columna; se aceptan ambos.
        id: _s(j, 'campana_id', 'campanas_id'),
        nombre: _s(j, 'nombre'),
        fechaInicio: _s(j, 'fecha_inicio'),
        fechaFin: _s(j, 'fecha_fin'),
      );

  factory Campana.fromDb(Map<String, Object?> r) =>
      Campana.fromJson(Map<String, dynamic>.from(r));

  Map<String, Object?> toDb() => {
        'campana_id': id,
        'nombre': nombre,
        'fecha_inicio': fechaInicio,
        'fecha_fin': fechaFin,
      };
}

class MaterialTextil {
  const MaterialTextil({
    required this.id,
    required this.codigo,
    required this.kardex,
    required this.descripcion,
    required this.tipo,
  });

  final String id;
  final String codigo;
  final String kardex;
  final String descripcion;
  final String tipo;

  String get detalle => [
        if (codigo.isNotEmpty) codigo,
        if (kardex.isNotEmpty) 'Kardex $kardex',
        if (tipo.isNotEmpty) tipo,
      ].join(' · ');

  factory MaterialTextil.fromJson(Map<String, dynamic> j) => MaterialTextil(
        // La tabla usa `codigo_material`; la especificación v2 decía `codigo_interno`.
        id: _s(j, 'material_id'),
        codigo: _s(j, 'codigo_material', 'codigo_interno'),
        kardex: _s(j, 'kardex_numero'),
        descripcion: _s(j, 'descripcion'),
        tipo: _s(j, 'tipo'),
      );

  factory MaterialTextil.fromDb(Map<String, Object?> r) =>
      MaterialTextil.fromJson(Map<String, dynamic>.from(r));

  Map<String, Object?> toDb() => {
        'material_id': id,
        'codigo_material': codigo,
        'kardex_numero': kardex,
        'descripcion': descripcion,
        'tipo': tipo,
      };
}

class Operario {
  const Operario({
    required this.id,
    required this.nombre,
    required this.pinHash,
    required this.almacenId,
  });

  final String id;
  final String nombre;
  final String pinHash;
  final String almacenId;

  String get iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  factory Operario.fromJson(Map<String, dynamic> j) => Operario(
        id: _s(j, 'operario_id'),
        nombre: _s(j, 'nombre_completo'),
        pinHash: _s(j, 'pin_hash'),
        almacenId: _s(j, 'almacen_id'),
      );

  factory Operario.fromDb(Map<String, Object?> r) =>
      Operario.fromJson(Map<String, dynamic>.from(r));

  Map<String, Object?> toDb() => {
        'operario_id': id,
        'nombre_completo': nombre,
        'pin_hash': pinHash,
        'almacen_id': almacenId,
      };
}

enum EstadoLibro {
  abierto('ABIERTO', 'Abierto'),
  pendienteEnvio('PENDIENTE_ENVIO', 'Pendiente de envío'),
  enviado('ENVIADO', 'Enviado');

  const EstadoLibro(this.db, this.etiqueta);
  final String db;
  final String etiqueta;

  static EstadoLibro desdeDb(Object? v) =>
      EstadoLibro.values.firstWhere((e) => e.db == v, orElse: () => abierto);
}

class Libro {
  const Libro({
    required this.id,
    required this.campanaId,
    required this.campanaNombre,
    required this.almacenId,
    required this.almacenNombre,
    required this.operarioId,
    required this.operarioNombre,
    required this.fechaCreacion,
    required this.estado,
    this.fechaCierre,
    this.fechaEnvio,
    this.intentosSync = 0,
    this.ultimoError,
    this.totalItems = 0,
    this.pesoTotal = 0,
  });

  final String id;
  final String campanaId;
  final String campanaNombre;
  final String almacenId;
  final String almacenNombre;
  final String operarioId;
  final String operarioNombre;
  final DateTime fechaCreacion;
  final DateTime? fechaCierre;
  final DateTime? fechaEnvio;
  final EstadoLibro estado;
  final int intentosSync;
  final String? ultimoError;
  final int totalItems;
  final double pesoTotal;

  static DateTime? _fecha(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory Libro.fromDb(Map<String, Object?> r) => Libro(
        id: r['libro_id'] as String,
        campanaId: r['campana_id'] as String,
        campanaNombre: r['campana_nombre'] as String,
        almacenId: r['almacen_id'] as String,
        almacenNombre: r['almacen_nombre'] as String,
        operarioId: r['operario_id'] as String,
        operarioNombre: r['operario_nombre'] as String,
        fechaCreacion: _fecha(r['fecha_creacion']) ?? DateTime.now(),
        fechaCierre: _fecha(r['fecha_cierre']),
        fechaEnvio: _fecha(r['fecha_envio']),
        estado: EstadoLibro.desdeDb(r['estado']),
        intentosSync: (r['intentos_sync'] as int?) ?? 0,
        ultimoError: r['ultimo_error'] as String?,
        totalItems: (r['total_items'] as int?) ?? 0,
        pesoTotal: ((r['peso_total'] as num?) ?? 0).toDouble(),
      );
}

class Movimiento {
  const Movimiento({
    required this.id,
    required this.libroId,
    required this.materialId,
    required this.materialCodigo,
    required this.materialDescripcion,
    required this.cantidad,
    required this.peso,
    required this.observacion,
    required this.fechaRegistro,
    required this.operarioId,
  });

  final String id;
  final String libroId;
  final String materialId;
  final String materialCodigo;
  final String materialDescripcion;
  final int cantidad;
  final double peso;
  final String? observacion;
  final DateTime fechaRegistro;
  final String operarioId;

  factory Movimiento.fromDb(Map<String, Object?> r) => Movimiento(
        id: r['movimiento_id'] as String,
        libroId: r['libro_id'] as String,
        materialId: r['material_id'] as String,
        materialCodigo: (r['material_codigo'] as String?) ?? '',
        materialDescripcion: r['material_descripcion'] as String,
        cantidad: r['cantidad_unidad'] as int,
        peso: (r['peso_neto'] as num).toDouble(),
        observacion: r['observacion'] as String?,
        fechaRegistro:
            DateTime.tryParse(r['fecha_registro'] as String) ?? DateTime.now(),
        operarioId: r['operario_id'] as String,
      );

  /// Fila de detalle en el cuerpo de POST /api/sync/upload.
  Map<String, Object?> toApi() => {
        'movimiento_id': id,
        'material_id': materialId,
        'cantidad_unidad': cantidad,
        'peso_neto': peso,
        'observacion': observacion,
        'fecha_registro': fechaRegistro.toUtc().toIso8601String(),
      };
}

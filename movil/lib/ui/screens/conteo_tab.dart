import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/formato.dart';
import '../../core/theme.dart';
import '../../data/repositories/libros_repository.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../widgets/material_picker.dart';

/// Pestaña principal: "Panel de Conteo y Captura" del mockup.
/// Sin libro abierto muestra el estado vacío; con libro abierto, el
/// formulario de captura y la lista de lo registrado.
class ConteoTab extends StatefulWidget {
  const ConteoTab({super.key});

  @override
  State<ConteoTab> createState() => _ConteoTabState();
}

class _ConteoTabState extends State<ConteoTab> {
  String? _claveCargada;
  bool _cargando = true;
  Libro? _libro;
  List<Movimiento> _movimientos = const [];

  // Formulario
  MaterialTextil? _material;
  final _cantidad = TextEditingController();
  final _peso = TextEditingController();
  final _obs = TextEditingController();
  final _focoCantidad = FocusNode();
  bool _guardando = false;

  @override
  void dispose() {
    _cantidad.dispose();
    _peso.dispose();
    _obs.dispose();
    _focoCantidad.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final app = context.read<AppState>();
    final almacenId = app.almacenId;
    final libro = almacenId == null ? null : await app.libros.abiertoDe(almacenId);
    final movs = libro == null ? const <Movimiento>[] : await app.libros.movimientos(libro.id);
    if (!mounted) return;
    setState(() {
      _libro = libro;
      _movimientos = movs;
      _cargando = false;
    });
  }

  void _aviso(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colores.error : null,
        duration: Duration(milliseconds: error ? 3000 : 1200),
      ));
  }

  // ------------------------------------------------------------ crear libro

  Future<void> _crearLibro() async {
    final app = context.read<AppState>();
    final almacen = app.almacenActual;
    final operario = app.operario;
    if (almacen == null || operario == null) return;

    final campanas = await app.maestros.campanas();
    if (!mounted) return;
    if (campanas.isEmpty) {
      _aviso('No hay campañas abiertas en el dispositivo. Actualiza los datos en Sync.',
          error: true);
      return;
    }
    final campana = campanas.length == 1
        ? campanas.first
        : await showModalBottomSheet<Campana>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('Elige la campaña',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  for (final cp in campanas)
                    ListTile(
                      minVerticalPadding: 14,
                      leading: const Icon(Icons.event_note_outlined),
                      title: Text(cp.nombre),
                      subtitle: Text('${cp.fechaInicio} → ${cp.fechaFin}'),
                      onTap: () => Navigator.pop(c, cp),
                    ),
                ],
              ),
            ),
          );
    if (campana == null) return;

    try {
      await app.libros.crear(campana: campana, almacen: almacen, operario: operario);
      await app.librosCambiaron();
    } on ReglaNegocioException catch (e) {
      _aviso(e.mensaje, error: true);
    }
  }

  // -------------------------------------------------------------- registrar

  Future<void> _elegirMaterial() async {
    final m = await MaterialPickerScreen.abrir(context);
    if (m != null && mounted) {
      setState(() => _material = m);
      _focoCantidad.requestFocus();
    }
  }

  Future<void> _registrar() async {
    final libro = _libro;
    final app = context.read<AppState>();
    final operario = app.operario;
    if (libro == null || operario == null || _guardando) return;

    final material = _material;
    final cantidad = int.tryParse(_cantidad.text.trim());
    final peso = parsePeso(_peso.text);
    if (material == null) {
      _aviso('Elige un material.', error: true);
      return;
    }
    if (cantidad == null || cantidad < 0) {
      _aviso('Ingresa una cantidad válida (número entero).', error: true);
      return;
    }
    if (peso == null || peso < 0) {
      _aviso('Ingresa un peso válido.', error: true);
      return;
    }

    if (peso > AppConfig.pesoAlertaKg) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Peso alto'),
          content: Text('Registraste ${kg(peso)}. ¿Es correcto?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Corregir')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, guardar')),
          ],
        ),
      );
      if (seguir != true) return;
    }

    setState(() => _guardando = true);
    try {
      await app.libros.agregarMovimiento(
        libroId: libro.id,
        material: material,
        cantidad: cantidad,
        peso: peso,
        observacion: _obs.text,
        operarioId: operario.id,
      );
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      _cantidad.clear();
      _peso.clear();
      _obs.clear();
      setState(() => _material = null);
      await app.librosCambiaron();
      _aviso('Registrado: ${material.descripcion}');
    } on ReglaNegocioException catch (e) {
      _aviso(e.mensaje, error: true);
    } catch (e) {
      _aviso('No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _borrarMovimiento(Movimiento m) async {
    final app = context.read<AppState>();
    // Dismissible exige quitar la fila del árbol en este mismo frame.
    setState(() => _movimientos = _movimientos.where((x) => x.id != m.id).toList());
    try {
      await app.libros.eliminarMovimiento(m);
      await app.librosCambiaron();
    } on ReglaNegocioException catch (e) {
      _aviso(e.mensaje, error: true);
      await _cargar(); // devuelve la fila si no se pudo borrar
    }
  }

  // ------------------------------------------------------------ cerrar libro

  Future<void> _cerrarLibro() async {
    final libro = _libro;
    if (libro == null) return;
    final app = context.read<AppState>();
    final total = _movimientos.fold<double>(0, (s, m) => s + m.peso);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cerrar el libro?'),
        content: Text(
          '${_movimientos.length} registros · ${kg(total)}\n\n'
          'Después de cerrarlo ya no se podrán agregar registros. '
          'Se enviará al servidor en cuanto haya conexión.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('btn-confirmar-cierre'),
            style: FilledButton.styleFrom(backgroundColor: Colores.exito),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cerrar libro'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await app.libros.cerrar(libro.id);
      await app.librosCambiaron();
      _aviso(app.conectividad.online
          ? 'Libro cerrado. Enviando…'
          : 'Libro cerrado. Se enviará cuando haya conexión.');
      app.sync.enviarPendientes(automatico: true);
    } on ReglaNegocioException catch (e) {
      _aviso(e.mensaje, error: true);
    }
  }

  Future<void> _descartarLibro() async {
    final libro = _libro;
    if (libro == null) return;
    final app = context.read<AppState>();
    try {
      await app.libros.descartarVacio(libro.id);
      await app.librosCambiaron();
    } on ReglaNegocioException catch (e) {
      _aviso(e.mensaje, error: true);
    }
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final clave = '${app.almacenId}|${app.revisionLibros}';
    if (clave != _claveCargada) {
      _claveCargada = clave;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cargar();
      });
    }

    final ancho = MediaQuery.sizeOf(context).width;
    final cabecera = <Widget>[
      const Text('Panel de Conteo y Captura',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colores.texto)),
      const SizedBox(height: 12),
      const _SelectorAlmacen(),
      const SizedBox(height: 16),
    ];

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_libro == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [...cabecera, _SinLibro(onCrear: app.almacenActual == null ? null : _crearLibro)],
      );
    }

    final formulario = _formulario();
    if (ancho >= 760) {
      // Tablet en horizontal: captura a la izquierda, registros a la derecha.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [...cabecera, _tarjetaLibro(), const SizedBox(height: 16), formulario],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 6,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(child: _tituloLista()),
                ),
                _listaMovimientos(),
              ],
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList.list(children: [
            ...cabecera,
            _tarjetaLibro(),
            const SizedBox(height: 16),
            formulario,
            const SizedBox(height: 24),
            _tituloLista(),
            const SizedBox(height: 8),
          ]),
        ),
        _listaMovimientos(),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _tarjetaLibro() {
    final l = _libro!;
    final total = _movimientos.fold<double>(0, (s, m) => s + m.peso);
    return Container(
      decoration: decoracionTarjeta(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colores.primarioSuave,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book_outlined, color: Colores.primario),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.campanaNombre,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('Abierto ${fechaHora(l.fechaCreacion)} · ${l.operarioNombre}',
                        style: const TextStyle(color: Colores.textoSuave, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'descartar') _descartarLibro();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'descartar',
                    enabled: _movimientos.isEmpty,
                    child: const Text('Descartar libro vacío'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('${_movimientos.length} registros · ${kg(total)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              FilledButton.icon(
                key: const Key('btn-cerrar-libro'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colores.exito,
                  minimumSize: const Size(48, 44),
                ),
                onPressed: _movimientos.isEmpty ? null : _cerrarLibro,
                icon: const Icon(Icons.task_alt, size: 20),
                label: const Text('Cerrar libro'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formulario() {
    return Container(
      decoration: decoracionTarjeta(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nuevo registro',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('campo-material'),
            borderRadius: BorderRadius.circular(10),
            onTap: _elegirMaterial,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Material',
                prefixIcon: Icon(Icons.search),
                suffixIcon: Icon(Icons.chevron_right),
              ),
              isEmpty: _material == null,
              child: _material == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_material!.descripcion,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(_material!.detalle,
                            style: const TextStyle(color: Colores.textoSuave, fontSize: 13)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('campo-cantidad'),
                  controller: _cantidad,
                  focusNode: _focoCantidad,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(labelText: 'Cantidad (und)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('campo-peso'),
                  controller: _peso,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,3}')),
                  ],
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(labelText: 'Peso neto (kg)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('campo-observacion'),
            controller: _obs,
            maxLength: 200,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _registrar(),
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              hintText: 'Ej: bolsa dañada, cono roto',
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              key: const Key('btn-registrar'),
              onPressed: _guardando ? null : _registrar,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Registrar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tituloLista() => Text(
        _movimientos.isEmpty ? 'Aún no hay registros' : 'Registrados (${_movimientos.length})',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      );

  Widget _listaMovimientos() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: _movimientos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final m = _movimientos[i];
          return Dismissible(
            key: ValueKey(m.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colores.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            confirmDismiss: (_) => showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('¿Borrar este registro?'),
                content: Text('${m.materialDescripcion}\n${m.cantidad} und · ${kg(m.peso)}'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
                ],
              ),
            ),
            onDismissed: (_) => _borrarMovimiento(m),
            child: _FilaMovimiento(m),
          );
        },
      ),
    );
  }
}

class _FilaMovimiento extends StatelessWidget {
  const _FilaMovimiento(this.m);
  final Movimiento m;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decoracionTarjeta(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.materialDescripcion, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [if (m.materialCodigo.isNotEmpty) m.materialCodigo, hora(m.fechaRegistro)]
                      .join(' · '),
                  style: const TextStyle(color: Colores.textoSuave, fontSize: 13),
                ),
                if (m.observacion != null)
                  Text(m.observacion!,
                      style: const TextStyle(
                          color: Colores.textoSuave, fontSize: 13, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${m.cantidad} und', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(kg(m.peso), style: const TextStyle(color: Colores.textoSuave)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Selector de almacén con botón de favorito (estrella), como en el mockup.
class _SelectorAlmacen extends StatelessWidget {
  const _SelectorAlmacen();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final esFavorito = app.almacenId != null && app.almacenId == app.almacenFavoritoId;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: decoracionTarjeta(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: app.almacenId,
                isExpanded: true,
                hint: const Text('Sin almacenes'),
                icon: const Icon(Icons.keyboard_arrow_down),
                borderRadius: BorderRadius.circular(12),
                items: [
                  for (final a in app.almacenes)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        a.detalle.isEmpty ? a.nombre : '${a.nombre} · ${a.detalle}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) app.seleccionarAlmacen(id);
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          height: 52,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colores.borde),
            ),
            child: IconButton(
              tooltip: esFavorito ? 'Quitar como predeterminado' : 'Usar como predeterminado',
              onPressed: app.almacenId == null ? null : app.alternarFavorito,
              icon: Icon(
                esFavorito ? Icons.star : Icons.star_border,
                color: esFavorito ? const Color(0xFFF59E0B) : Colores.texto,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SinLibro extends StatelessWidget {
  const _SinLibro({required this.onCrear});
  final VoidCallback? onCrear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decoracionTarjeta(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colores.primarioSuave,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.menu_book_outlined, color: Colores.primario, size: 28),
          ),
          const SizedBox(height: 20),
          const Text('No hay libro de conteo activo',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Crea un nuevo libro para comenzar a registrar movimientos. El almacén y la '
            'fecha se asignan automáticamente al crearlo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colores.textoSuave, height: 1.45),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('btn-crear-libro'),
              onPressed: onCrear,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Crear nuevo libro de conteo'),
            ),
          ),
        ],
      ),
    );
  }
}

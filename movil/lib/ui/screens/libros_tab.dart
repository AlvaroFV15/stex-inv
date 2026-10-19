import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/theme.dart';
import '../../data/repositories/libros_repository.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../widgets/estado_chip.dart';

/// Historial de libros del dispositivo: abiertos, pendientes y enviados
/// (los enviados se borran solos a los 7 días).
class LibrosTab extends StatefulWidget {
  const LibrosTab({super.key, required this.visible});
  final bool visible;

  @override
  State<LibrosTab> createState() => _LibrosTabState();
}

class _LibrosTabState extends State<LibrosTab> {
  String? _claveCargada;
  List<Libro>? _libros;

  Future<void> _cargar() async {
    final r = await context.read<AppState>().libros.todos();
    if (mounted) setState(() => _libros = r);
  }

  @override
  Widget build(BuildContext context) {
    final revision = context.select<AppState, int>((s) => s.revisionLibros);
    final clave = '$revision|${widget.visible}';
    if (widget.visible && clave != _claveCargada) {
      _claveCargada = clave;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cargar();
      });
    }

    final libros = _libros;
    if (libros == null) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _cargar,
      child: libros.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.menu_book_outlined, size: 48, color: Colores.textoSuave),
                SizedBox(height: 12),
                Text('Todavía no hay libros en este dispositivo.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colores.textoSuave)),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: libros.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return const Text('Libros de conteo',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700));
                }
                final l = libros[i - 1];
                return _TarjetaLibro(
                  libro: l,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LibroDetalleScreen(libroId: l.id),
                  )),
                );
              },
            ),
    );
  }
}

class _TarjetaLibro extends StatelessWidget {
  const _TarjetaLibro({required this.libro, required this.onTap});
  final Libro libro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = libro;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colores.borde),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l.campanaNombre,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  EstadoChip(l.estado, conError: l.ultimoError != null),
                ],
              ),
              const SizedBox(height: 4),
              Text('${l.almacenNombre} · ${l.operarioNombre}',
                  style: const TextStyle(color: Colores.textoSuave)),
              const SizedBox(height: 4),
              Text(
                '${fechaHora(l.fechaCreacion)} · ${l.totalItems} registros · ${kg(l.pesoTotal)}',
                style: const TextStyle(color: Colores.textoSuave, fontSize: 13),
              ),
              if (l.estado == EstadoLibro.pendienteEnvio && l.ultimoError != null) ...[
                const SizedBox(height: 6),
                Text('Último intento: ${l.ultimoError}',
                    style: const TextStyle(color: Colores.error, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Detalle de un libro. Si está pendiente de envío se puede reabrir para
/// corregirlo.
class LibroDetalleScreen extends StatefulWidget {
  const LibroDetalleScreen({super.key, required this.libroId});
  final String libroId;

  @override
  State<LibroDetalleScreen> createState() => _LibroDetalleScreenState();
}

class _LibroDetalleScreenState extends State<LibroDetalleScreen> {
  Libro? _libro;
  List<Movimiento> _movs = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final repo = context.read<AppState>().libros;
    final l = await repo.porId(widget.libroId);
    final m = l == null ? const <Movimiento>[] : await repo.movimientos(l.id);
    if (mounted) {
      setState(() {
        _libro = l;
        _movs = m;
      });
    }
  }

  Future<void> _reabrir() async {
    final app = context.read<AppState>();
    final libro = _libro!;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await app.libros.reabrir(libro);
      app.seleccionarAlmacen(libro.almacenId);
      await app.librosCambiaron();
      nav.pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('Libro reabierto. Corrígelo en la pestaña Conteo.')));
    } on ReglaNegocioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _libro;
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del libro')),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: decoracionTarjeta(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(l.campanaNombre,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                        EstadoChip(l.estado, conError: l.ultimoError != null),
                      ]),
                      const SizedBox(height: 8),
                      _dato('Almacén', l.almacenNombre),
                      _dato('Operario', l.operarioNombre),
                      _dato('Creado', fechaHora(l.fechaCreacion)),
                      if (l.fechaCierre != null) _dato('Cerrado', fechaHora(l.fechaCierre!)),
                      if (l.fechaEnvio != null) _dato('Enviado', fechaHora(l.fechaEnvio!)),
                      _dato('Total', '${l.totalItems} registros · ${kg(l.pesoTotal)}'),
                      if (l.ultimoError != null)
                        _dato('Último error', '${l.ultimoError} (${l.intentosSync} intentos)'),
                      if (l.estado == EstadoLibro.pendienteEnvio) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _reabrir,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Reabrir para corregir'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final m in _movs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: decoracionTarjeta(),
                      child: ListTile(
                        title: Text(m.materialDescripcion,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          if (m.materialCodigo.isNotEmpty) m.materialCodigo,
                          hora(m.fechaRegistro),
                          if (m.observacion != null) m.observacion!,
                        ].join(' · ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${m.cantidad} und',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(kg(m.peso)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _dato(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(etiqueta, style: const TextStyle(color: Colores.textoSuave)),
            ),
            Expanded(child: Text(valor)),
          ],
        ),
      );
}

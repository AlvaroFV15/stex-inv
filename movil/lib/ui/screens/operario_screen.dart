import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../widgets/app_header.dart';
import '../widgets/pin_pad.dart';

/// Paso 3: el operario se elige de la lista y firma con su PIN (offline).
class OperarioScreen extends StatefulWidget {
  const OperarioScreen({super.key});

  @override
  State<OperarioScreen> createState() => _OperarioScreenState();
}

class _OperarioScreenState extends State<OperarioScreen> {
  List<Operario>? _operarios;
  String _filtro = '';
  bool _actualizando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await context.read<AppState>().maestros.operarios();
    if (mounted) setState(() => _operarios = lista);
  }

  Future<void> _actualizarMaestros() async {
    setState(() => _actualizando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().actualizarMaestros();
      await _cargar();
      messenger.showSnackBar(const SnackBar(content: Text('Datos actualizados.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  void _pedirPin(Operario o) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaPin(operario: o),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = (_operarios ?? const <Operario>[])
        .where((o) => o.nombre.toLowerCase().contains(_filtro.toLowerCase()))
        .toList();

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(mostrarAlmacen: false),
          Expanded(
            child: _operarios == null
                ? const Center(child: CircularProgressIndicator())
                : _operarios!.isEmpty
                    ? _SinOperarios(actualizando: _actualizando, onActualizar: _actualizarMaestros)
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('¿Quién inicia turno?',
                                      style: TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  const Text('Toca tu nombre e ingresa tu PIN de 4 dígitos.',
                                      style: TextStyle(color: Colores.textoSuave)),
                                  if (_operarios!.length > 8) ...[
                                    const SizedBox(height: 16),
                                    TextField(
                                      onChanged: (v) => setState(() => _filtro = v),
                                      decoration: const InputDecoration(
                                        hintText: 'Buscar por nombre',
                                        prefixIcon: Icon(Icons.search),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverGrid.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisExtent: 132,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              ),
                              itemCount: lista.length,
                              itemBuilder: (_, i) => _TarjetaOperario(
                                key: Key('operario-${lista[i].id}'),
                                operario: lista[i],
                                onTap: () => _pedirPin(lista[i]),
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaOperario extends StatelessWidget {
  const _TarjetaOperario({super.key, required this.operario, required this.onTap});

  final Operario operario;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colores.primarioSuave,
                child: Text(operario.iniciales,
                    style: const TextStyle(
                        color: Colores.primario, fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              const SizedBox(height: 10),
              Text(
                operario.nombre,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HojaPin extends StatefulWidget {
  const _HojaPin({required this.operario});
  final Operario operario;

  @override
  State<_HojaPin> createState() => _HojaPinState();
}

class _HojaPinState extends State<_HojaPin> {
  final _pad = GlobalKey<PinPadState>();
  String? _error;

  void _validar(String pin) {
    final r = context.read<AppState>().ingresar(widget.operario, pin);
    if (r.ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = r.mensaje);
      _pad.currentState?.limpiar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.operario.nombre,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Ingresa tu PIN', style: TextStyle(color: Colores.textoSuave)),
            const SizedBox(height: 20),
            PinPad(key: _pad, error: _error, alCompletar: _validar),
          ],
        ),
      ),
    );
  }
}

class _SinOperarios extends StatelessWidget {
  const _SinOperarios({required this.actualizando, required this.onActualizar});

  final bool actualizando;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 56, color: Colores.textoSuave),
            const SizedBox(height: 12),
            const Text('No hay operarios en este dispositivo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Registra al personal del almacén en el panel web (Personal de Planta) '
              'y luego actualiza los datos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colores.textoSuave),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: actualizando ? null : onActualizar,
              icon: const Icon(Icons.sync),
              label: Text(actualizando ? 'Actualizando…' : 'Actualizar datos'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';

/// Pantalla completa de búsqueda de material por código, kardex o descripción.
/// Devuelve el [MaterialTextil] elegido con Navigator.pop.
class MaterialPickerScreen extends StatefulWidget {
  const MaterialPickerScreen({super.key});

  static Future<MaterialTextil?> abrir(BuildContext context) =>
      Navigator.of(context).push<MaterialTextil>(
        MaterialPageRoute(builder: (_) => const MaterialPickerScreen()),
      );

  @override
  State<MaterialPickerScreen> createState() => _MaterialPickerScreenState();
}

class _MaterialPickerScreenState extends State<MaterialPickerScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<MaterialTextil> _resultados = const [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _alEscribir(String texto) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () => _buscar(texto));
  }

  Future<void> _buscar(String texto) async {
    final r = await context.read<AppState>().maestros.buscarMateriales(texto);
    if (!mounted) return;
    setState(() {
      _resultados = r;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar material')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('campo-buscar-material'),
              controller: _ctrl,
              autofocus: true,
              onChanged: _alEscribir,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Código, N.° de kardex o descripción',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _ctrl.clear();
                    _buscar('');
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _resultados.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Sin resultados. Si el material es nuevo, actualiza los '
                            'datos maestros desde la pestaña Sync.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colores.textoSuave),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _resultados.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final m = _resultados[i];
                          return ListTile(
                            key: Key('material-${m.id}'),
                            minVerticalPadding: 14,
                            title: Text(m.descripcion,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(m.detalle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).pop(m),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formato.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../state/conectividad.dart';

/// Estado de la sincronización: libros pendientes, envío manual,
/// actualización de datos maestros y reautenticación si la sesión expiró.
class SyncTab extends StatefulWidget {
  const SyncTab({super.key});

  @override
  State<SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends State<SyncTab> {
  Map<String, int>? _conteos;
  String? _ultimaDescarga;
  int? _revisionCargada;

  Future<void> _cargarMaestros() async {
    final m = context.read<AppState>().maestros;
    final c = await m.conteos();
    final u = await m.meta('ultima_descarga');
    if (mounted) {
      setState(() {
        _conteos = c;
        _ultimaDescarga = u;
      });
    }
  }

  Future<void> _actualizarMaestros() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().actualizarMaestros();
      await _cargarMaestros();
      messenger.showSnackBar(const SnackBar(content: Text('Datos maestros actualizados.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _reautenticar() async {
    final app = context.read<AppState>();
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoPassword(email: app.emailVinculado ?? '-'),
    );
    if (password == null || password.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await app.reautenticar(password);
      messenger.showSnackBar(const SnackBar(content: Text('Sesión renovada.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final online = context.watch<Conectividad>().online;
    final sync = app.sync;

    if (_revisionCargada != app.revisionLibros) {
      _revisionCargada = app.revisionLibros;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cargarMaestros();
      });
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Sincronización',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),

        if (sync.sesionInvalida) ...[
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFDECEA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colores.error),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('La sesión del dispositivo expiró',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colores.error)),
                const SizedBox(height: 6),
                const Text(
                    'Los libros siguen guardados. Ingresa la contraseña del almacén para '
                    'poder enviarlos.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: online ? _reautenticar : null,
                  child: const Text('Volver a autenticar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ---- Envío de libros
        Container(
          decoration: decoracionTarjeta(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      color: online ? Colores.exito : Colores.alerta, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      online ? 'Conectado · listo para sincronizar' : 'Sin conexión',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                sync.pendientes == 0
                    ? 'No hay libros pendientes de envío.'
                    : sync.pendientes == 1
                        ? '1 libro cerrado espera envío.'
                        : '${sync.pendientes} libros cerrados esperan envío.',
                style: const TextStyle(fontSize: 15),
              ),
              if (sync.ultimoEnvioOk != null)
                Text('Último envío correcto: ${fechaHora(sync.ultimoEnvioOk!)}',
                    style: const TextStyle(color: Colores.textoSuave)),
              if (sync.ultimoMensaje != null) ...[
                const SizedBox(height: 8),
                Text(sync.ultimoMensaje!,
                    style: TextStyle(
                      color: sync.ultimoFueError ? Colores.error : Colores.exito,
                      fontWeight: FontWeight.w600,
                    )),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('btn-enviar-libros'),
                onPressed: (!online || sync.enviando || sync.pendientes == 0)
                    ? null
                    : () => sync.enviarPendientes(),
                icon: sync.enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(sync.enviando ? 'Enviando…' : 'Enviar libros ahora'),
              ),
              const SizedBox(height: 8),
              const Text(
                'El envío también se hace solo al recuperar la conexión.',
                style: TextStyle(color: Colores.textoSuave, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- Datos maestros
        Container(
          decoration: decoracionTarjeta(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Datos maestros',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              if (_conteos != null)
                Text(
                  '${_conteos!['campanas']} campañas · ${_conteos!['almacenes']} almacenes · '
                  '${_conteos!['materiales']} materiales · ${_conteos!['operarios']} operarios',
                ),
              if (_ultimaDescarga != null)
                Text(
                  'Última descarga: ${fechaHora(DateTime.tryParse(_ultimaDescarga!) ?? DateTime.now())}',
                  style: const TextStyle(color: Colores.textoSuave),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: (!online || sync.descargando) ? null : _actualizarMaestros,
                icon: sync.descargando
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                label: Text(sync.descargando ? 'Descargando…' : 'Actualizar datos maestros'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DialogoPassword extends StatefulWidget {
  const _DialogoPassword({required this.email});
  final String email;

  @override
  State<_DialogoPassword> createState() => _DialogoPasswordState();
}

class _DialogoPasswordState extends State<_DialogoPassword> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Volver a autenticar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cuenta: ${widget.email}'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Contraseña del almacén'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Ingresar'),
        ),
      ],
    );
  }
}

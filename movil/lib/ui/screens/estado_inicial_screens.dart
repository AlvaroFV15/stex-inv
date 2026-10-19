import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';

class CargandoScreen extends StatelessWidget {
  const CargandoScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colores.cabecera,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({
    required this.icono,
    required this.titulo,
    required this.texto,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icono, size: 56, color: Colores.alerta),
                    const SizedBox(height: 16),
                    Text(titulo,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(texto,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colores.textoSuave, height: 1.4)),
                    if (accion != null) ...[const SizedBox(height: 24), accion!],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class ConfigFaltanteScreen extends StatelessWidget {
  const ConfigFaltanteScreen({super.key});

  @override
  Widget build(BuildContext context) => const _Mensaje(
        icono: Icons.settings_outlined,
        titulo: 'Falta configuración',
        texto: 'Compila la app con SUPABASE_URL, SUPABASE_ANON_KEY y API_BASE_URL:\n\n'
            'flutter run --dart-define-from-file=dart_defines.json',
      );
}

class ErrorBaseLocalScreen extends StatelessWidget {
  const ErrorBaseLocalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return _Mensaje(
      icono: Icons.error_outline,
      titulo: 'No se pudo abrir la base de datos local',
      texto: 'La clave de cifrado del dispositivo no coincide con la base guardada. '
          'Esto pasa si se restauró una copia de seguridad del teléfono.\n\n'
          'Detalle: ${app.detalleError ?? '-'}',
      accion: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Colores.error),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('¿Reiniciar el dispositivo?'),
              content: const Text(
                  'Se borrarán los datos locales que no se hayan enviado y habrá que '
                  'vincular el dispositivo otra vez.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reiniciar')),
              ],
            ),
          );
          if (ok == true) await app.reiniciarBaseLocal();
        },
        child: const Text('Reiniciar datos del dispositivo'),
      ),
    );
  }
}

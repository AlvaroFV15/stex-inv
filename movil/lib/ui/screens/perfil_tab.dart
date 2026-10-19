import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';

class PerfilTab extends StatelessWidget {
  const PerfilTab({super.key});

  Future<void> _desvincular(BuildContext context) async {
    final app = context.read<AppState>();
    final sinEnviar = await app.libros.contarSinEnviar();
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Desvincular este dispositivo?'),
        content: Text(sinEnviar > 0
            ? 'ATENCIÓN: hay $sinEnviar libros que no llegaron al servidor. '
                'Si desvinculas ahora se perderán.\n\n'
                'Envíalos primero desde la pestaña Sync.'
            : 'Se borrarán los datos del dispositivo y habrá que ingresar otra vez '
                'la cuenta del almacén.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colores.error),
            onPressed: () => Navigator.pop(c, true),
            child: Text(sinEnviar > 0 ? 'Desvincular y perder datos' : 'Desvincular'),
          ),
        ],
      ),
    );
    if (ok == true) await app.desvincular();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final op = app.operario;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: decoracionTarjeta(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colores.primarioSuave,
                child: Text(op?.iniciales ?? '?',
                    style: const TextStyle(
                        color: Colores.primario, fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              Text(op?.nombre ?? '-',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Operario en turno', style: TextStyle(color: Colores.textoSuave)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: app.cerrarTurno,
                  icon: const Icon(Icons.logout),
                  label: const Text('Terminar turno / cambiar operario'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: decoracionTarjeta(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Dispositivo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Vinculado a: ${app.emailVinculado ?? '-'}'),
              const SizedBox(height: 4),
              const Text(
                'Los datos de este dispositivo están cifrados. Desvincular borra todo lo '
                'guardado localmente.',
                style: TextStyle(color: Colores.textoSuave, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colores.error),
                onPressed: () => _desvincular(context),
                icon: const Icon(Icons.link_off),
                label: const Text('Desvincular dispositivo'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text('STEX-INV Móvil v1.0.0',
              style: TextStyle(color: Colores.textoSuave, fontSize: 12)),
        ),
      ],
    );
  }
}

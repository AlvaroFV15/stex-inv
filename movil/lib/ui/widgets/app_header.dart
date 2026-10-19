import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../state/conectividad.dart';

/// Barra superior del mockup: logo, empresa, almacén y estado de red.
/// Cuando no hay red muestra además una franja naranja de "modo offline".
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.mostrarAlmacen = true});

  final bool mostrarAlmacen;

  @override
  Widget build(BuildContext context) {
    final online = context.watch<Conectividad>().online;
    final almacen = mostrarAlmacen ? context.watch<AppState>().almacenActual : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: Colores.cabecera,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colores.marca,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.factory_outlined, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'APJL S.A.C.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: almacen == null
                          ? const SizedBox.shrink()
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Icon(Icons.warehouse_outlined,
                                    color: Color(0xFFCBD5E1), size: 18),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    almacen.nombre,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFFE2E8F0), fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: online ? 'Conectado' : 'Sin conexión',
                      child: Icon(
                        online ? Icons.wifi : Icons.wifi_off,
                        color: online ? const Color(0xFF4ADE80) : Colores.alerta,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: online
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  color: Colores.alerta,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: const Text(
                    'Modo offline · los conteos se guardan en el dispositivo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
        ),
      ],
    );
  }
}

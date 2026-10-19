import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';

class EstadoChip extends StatelessWidget {
  const EstadoChip(this.estado, {super.key, this.conError = false});

  final EstadoLibro estado;
  final bool conError;

  @override
  Widget build(BuildContext context) {
    final (Color fondo, Color texto, String etiqueta) = switch (estado) {
      EstadoLibro.abierto => (const Color(0xFFE8EFFD), Colores.primario, estado.etiqueta),
      EstadoLibro.pendienteEnvio => conError
          ? (const Color(0xFFFDECEA), Colores.error, 'Error al enviar')
          : (const Color(0xFFFFF3E0), const Color(0xFFB45309), estado.etiqueta),
      EstadoLibro.enviado => (const Color(0xFFE8F5E9), Colores.exito, estado.etiqueta),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: Text(etiqueta,
          style: TextStyle(color: texto, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

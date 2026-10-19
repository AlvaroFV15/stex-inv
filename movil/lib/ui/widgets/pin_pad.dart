import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Teclado numérico táctil con botones grandes (≥ 64 dp) y vibración en cada
/// pulsación. Llama a [alCompletar] cuando se ingresan [longitud] dígitos.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.alCompletar,
    this.longitud = 4,
    this.error,
    this.habilitado = true,
  });

  final void Function(String pin) alCompletar;
  final int longitud;
  final String? error;
  final bool habilitado;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';

  void limpiar() => setState(() => _pin = '');

  void _tocar(String d) {
    if (!widget.habilitado || _pin.length >= widget.longitud) return;
    HapticFeedback.lightImpact();
    setState(() => _pin += d);
    if (_pin.length == widget.longitud) {
      final pin = _pin;
      // Deja ver el último punto relleno antes de validar.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) widget.alCompletar(pin);
      });
    }
  }

  void _borrar() {
    if (_pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.longitud, (i) {
            final lleno = i < _pin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lleno ? Colores.primario : Colors.transparent,
                border: Border.all(
                  color: widget.error != null ? Colores.error : Colores.primario,
                  width: 2,
                ),
              ),
            );
          }),
        ),
        SizedBox(
          height: 44,
          child: Center(
            child: widget.error == null
                ? null
                : Text(
                    widget.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colores.error, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        for (final fila in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in fila) _Tecla(key: Key('tecla-$d'), texto: d, onTap: () => _tocar(d)),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 88, height: 72),
            _Tecla(key: const Key('tecla-0'), texto: '0', onTap: () => _tocar('0')),
            _Tecla(key: const Key('tecla-borrar'), icono: Icons.backspace_outlined, onTap: _borrar),
          ],
        ),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  const _Tecla({super.key, this.texto, this.icono, required this.onTap});

  final String? texto;
  final IconData? icono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 76,
        height: 60,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colores.borde),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Center(
              child: texto != null
                  ? Text(texto!,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))
                  : Icon(icono, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

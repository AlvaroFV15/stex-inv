import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../state/conectividad.dart';
import '../widgets/app_header.dart';

/// Paso 1: vinculación del dispositivo con la cuenta del almacén.
/// Se hace una sola vez; luego la app va directo a la selección de operario.
class VincularScreen extends StatefulWidget {
  const VincularScreen({super.key});

  @override
  State<VincularScreen> createState() => _VincularScreenState();
}

class _VincularScreenState extends State<VincularScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _verPassword = false;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: context.read<AppState>().emailVinculado ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await context.read<AppState>().vincular(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<Conectividad>().online;
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(mostrarAlmacen: false),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Vincular dispositivo',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text(
                          'Ingresa la cuenta del almacén. Solo se pide una vez: después, '
                          'cada operario entra con su PIN aunque no haya internet.',
                          style: TextStyle(color: Colores.textoSuave, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const Key('campo-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Correo del almacén',
                            hintText: 'almacen1@apjltextil.com',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? 'Ingresa un correo válido'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('campo-password'),
                          controller: _password,
                          obscureText: !_verPassword,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _vincular(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_verPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () => setState(() => _verPassword = !_verPassword),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Ingresa la contraseña' : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!,
                              style: const TextStyle(
                                  color: Colores.error, fontWeight: FontWeight.w600)),
                        ],
                        if (!online) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Sin conexión: conéctate a internet para vincular.',
                            style: TextStyle(color: Colores.alerta, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const Key('btn-vincular'),
                          onPressed: _cargando || !online ? null : _vincular,
                          child: _cargando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Text('Vincular y descargar datos'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

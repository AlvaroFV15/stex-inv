import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'state/app_state.dart';
import 'state/conectividad.dart';
import 'ui/screens/estado_inicial_screens.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/operario_screen.dart';
import 'ui/screens/vincular_screen.dart';

class StexApp extends StatelessWidget {
  const StexApp({super.key});

  @override
  Widget build(BuildContext context) {
    final fase = context.select<AppState, Fase>((s) => s.fase);
    return MaterialApp(
      title: 'STEX-INV',
      debugShowCheckedModeBanner: false,
      theme: construirTema(),
      home: switch (fase) {
        Fase.cargando => const CargandoScreen(),
        Fase.configFaltante => const ConfigFaltanteScreen(),
        Fase.errorBaseLocal => const ErrorBaseLocalScreen(),
        Fase.sinVincular => const VincularScreen(),
        Fase.sinOperario => const OperarioScreen(),
        Fase.listo => const HomeShell(),
      },
    );
  }
}

/// Providers + app. Las pruebas de widgets usan este mismo árbol.
class StexRaiz extends StatelessWidget {
  const StexRaiz({super.key, required this.conectividad, required this.app});

  final Conectividad conectividad;
  final AppState app;

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider<Conectividad>.value(value: conectividad),
          ChangeNotifierProvider<AppState>.value(value: app),
        ],
        child: const StexApp(),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../widgets/app_header.dart';
import 'conteo_tab.dart';
import 'libros_tab.dart';
import 'perfil_tab.dart';
import 'sync_tab.dart';

/// Contenedor principal con la barra inferior del mockup:
/// Conteo · Libros · Sync · Perfil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _indice = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app, intenta enviar lo pendiente.
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().sync.enviarPendientes(automatico: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = context.select<AppState, int>((s) => s.sync.pendientes);
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: IndexedStack(
              index: _indice,
              children: [
                const ConteoTab(),
                LibrosTab(visible: _indice == 1),
                const SyncTab(),
                const PerfilTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        backgroundColor: Colors.white,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.view_in_ar_outlined),
            selectedIcon: Icon(Icons.view_in_ar),
            label: 'Conteo',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Libros',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendientes > 0,
              label: Text('$pendientes'),
              backgroundColor: const Color(0xFFEA580C),
              child: const Icon(Icons.sync),
            ),
            label: 'Sync',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

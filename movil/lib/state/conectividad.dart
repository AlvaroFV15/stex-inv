import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Estado de la red. "online" solo indica que hay una interfaz conectada
/// (Wi-Fi, datos, ethernet); que el servidor responda se comprueba al
/// sincronizar.
abstract class Conectividad extends ChangeNotifier {
  bool get online;
}

/// Implementación real con connectivity_plus.
class ConectividadDispositivo extends Conectividad {
  ConectividadDispositivo([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _online = false;

  @override
  bool get online => _online;

  Future<void> iniciar() async {
    try {
      _actualizar(await _connectivity.checkConnectivity());
    } catch (_) {
      _actualizar(const [ConnectivityResult.none]);
    }
    _sub = _connectivity.onConnectivityChanged.listen(_actualizar);
  }

  void _actualizar(List<ConnectivityResult> resultados) {
    final nuevo = resultados.any((r) => r != ConnectivityResult.none);
    if (nuevo != _online) {
      _online = nuevo;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

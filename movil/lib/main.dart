import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/local/database.dart';
import 'data/local/secure_auth_storage.dart';
import 'data/local/secure_store.dart';
import 'data/remote/api_client.dart';
import 'data/remote/auth_service.dart';
import 'state/app_state.dart';
import 'state/conectividad.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.completa) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureAuthStorage(),
        autoRefreshToken: true,
      ),
    );
  }

  final conectividad = ConectividadDispositivo();
  await conectividad.iniciar();

  final auth = SupabaseAuthService();
  final app = AppState(
    conectividad: conectividad,
    auth: auth,
    api: ApiClient(auth, baseUrl: AppConfig.apiBaseUrl),
    seguro: const SecureStore(),
    abrirBase: AppDatabase.abrirCifrada,
    eliminarBase: AppDatabase.eliminarCifrada,
    configCompleta: AppConfig.completa,
  );

  runApp(StexRaiz(conectividad: conectividad, app: app));
  await app.iniciar();
}

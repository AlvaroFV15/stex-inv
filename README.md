# STEX-INV · App móvil + entorno Docker de pruebas

App de conteo de inventario **offline-first** para APJL Textil (Flutter, Android e iOS), con:
- un **servidor local en Docker** que imita Supabase Auth y la API `/api/sync` del panel;
- **pruebas unitarias, de widgets, de integración y punta a punta**;
- el **parche del panel Next.js** listo para producción, con su Dockerfile.

## Requisitos

| Para… | Necesitas |
|---|---|
| Levantar el servidor y correr todas las pruebas | Docker Desktop (con Docker Compose) |
| Ver la app en un emulador o celular | Flutter SDK + Android Studio |
| `make` | Linux/macOS; en Windows usa los comandos `docker compose` que están en el Makefile |

## Inicio rápido

```bash
cp .env.example .env          # opcional: cambiar puertos
make up                       # PostgreSQL + API en http://localhost:8080
make test                     # todas las pruebas (servidor, app, integración)
```

Cuentas de prueba (contraseña `Stex2026!`): `almacen1@apjltextil.com`, `almacen2@…`, `admin@…`.
PIN de Juan Carlos Pérez: `1234`. Detalle en [docs/PLAN_DE_PRUEBAS.md](docs/PLAN_DE_PRUEBAS.md).

## Ver la app en Android Studio contra el servidor de Docker

```bash
make up
cd movil
bash tool/preparar_plataformas.sh   # genera android/ e ios/ y aplica los ajustes
flutter pub get
```

En Android Studio: *File → Open → `movil/`*. En *Run → Edit Configurations → Additional run args* pon:

```
--dart-define-from-file=dart_defines.docker.json
```

- **Emulador:** ya apunta a `http://10.0.2.2:8080` (así ve el emulador a tu PC).
- **Celular real en la misma Wi-Fi:** copia `dart_defines.docker.json` a `dart_defines.json`, cambia `10.0.2.2` por la IP de tu PC (ej. `192.168.1.20`) y usa ese archivo.

El tráfico `http` solo está permitido en debug/profile; la versión release exige HTTPS.

## APK sin instalar Flutter

```bash
make apk                     # → dist/stex-inv-debug.apk (servidor local)
make apk-release URL=https://tu-panel SUPABASE_URL=https://xxx.supabase.co ANON_KEY=...
```

El APK release va firmado con la clave de debug de Flutter; para publicarlo en Play Store configura tu propia firma.

## Desplegar en producción

1. **Base de datos:** ejecuta `backend/parche-panel/supabase/migrations/20261018_sync_movil.sql` en Supabase → SQL Editor. Es idempotente.
2. **Panel Next.js:** copia `backend/parche-panel/lib/sync/` y `app/api/sync/` a tu proyecto, más `Dockerfile` y `.dockerignore`. Pon `output: "standalone"` en `next.config.ts` y luego:
   ```bash
   docker build --build-arg NEXT_PUBLIC_SUPABASE_URL=... --build-arg NEXT_PUBLIC_SUPABASE_ANON_KEY=... -t stex-panel .
   docker run -p 3000:3000 -e SUPABASE_SERVICE_ROLE_KEY=... -e DEFAULT_USER_PASSWORD=... stex-panel
   ```
3. **App:** compila con un `dart_defines.json` que apunte a Supabase real y al dominio HTTPS del panel.

Detalle en [backend/parche-panel/README.md](backend/parche-panel/README.md).

## Estructura

```
stex-inv/
├── docker-compose.yml          db · api · api-tests · movil-test · movil-integracion
├── Makefile                    atajos (up, test, apk…)
├── .github/workflows/ci.yml    las mismas pruebas en GitHub Actions
├── docs/PLAN_DE_PRUEBAS.md     niveles, trazabilidad HU → pruebas, aceptación manual
├── backend/
│   ├── db/                     compatibilidad Supabase, esquema y datos de prueba
│   ├── parche-panel/           lo que va al panel en producción
│   │   ├── lib/sync/           reglas de negocio (compartidas con el servidor local)
│   │   ├── app/api/sync/       rutas download y upload
│   │   ├── supabase/migrations/
│   │   └── Dockerfile
│   └── servidor-local/         Auth + /api/sync para pruebas (Node + PostgreSQL)
│       ├── src/  test/unit/  test/integracion/  Dockerfile
└── movil/                      app Flutter
    ├── lib/                    core · domain · data · state · ui
    ├── test/unit/              lógica, base local, sync, cliente HTTP, estado
    ├── test/widget/            pantallas y flujo completo
    ├── test/integration/       app ↔ servidor de Docker
    ├── integration_test/       punta a punta en emulador
    ├── tool/                   preparar_plataformas.sh · ci.sh
    └── Dockerfile              pruebas y APK
```

El servidor local no es un "mock" aparte: usa **el mismo código de negocio** (`backend/parche-panel/lib/sync`) y **la misma migración SQL** que producción. Si una regla cambia, cambia en los dos.

## Si algo falla

- **La imagen de Flutter no existe:** pon otra versión en `.env` (`FLUTTER_VERSION=3.47.7`); para `make apk` usa `docker build --build-arg FLUTTER_VERSION=3.47.7 …`. Las imágenes son `ghcr.io/cirruslabs/flutter:<versión>`.
- **`flutter pub get` no resuelve versiones:** ejecuta `flutter pub upgrade --major-versions` en `movil/` y vuelve a probar.
- **`flutter analyze` marca advertencias:** el código Flutter no se pudo compilar en el entorno donde se escribió. Pega aquí la salida y se corrige; la lógica está cubierta por las pruebas.
- **Puerto ocupado:** cambia `API_PORT` o `DB_PORT` en `.env`.
- **Empezar de cero:** `make limpiar`.

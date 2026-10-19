# Plan de pruebas · STEX-INV Móvil (sync v2.1)

## 1. Alcance

| Componente | Qué se prueba |
|---|---|
| App Flutter (`movil/`) | Lógica, base local, sincronización, pantallas y flujo completo |
| Reglas de sincronización (`backend/parche-panel/lib/sync`) | Validación, aislamiento por almacén, idempotencia, errores |
| Migración SQL (`registrar_libro_conteo`) | Transacción atómica, idempotencia, permisos del rol `authenticated` |
| Servidor local (`backend/servidor-local`) | Auth compatible con Supabase y endpoints `/api/sync/*` |

Fuera de alcance: el resto del panel web (campañas, materiales, etc.) y las políticas RLS reales de Supabase, que no están en el repositorio.

## 2. Niveles de prueba

| Nivel | Herramienta | Dónde | Cantidad |
|---|---|---|---|
| Unitarias del servidor | `node:test` | `backend/servidor-local/test/unit` | 51 |
| Integración del servidor (HTTP + PostgreSQL real) | `node:test` | `backend/servidor-local/test/integracion` | 34 |
| Unitarias de la app (SQLite real en memoria/archivo) | `flutter_test` | `movil/test/unit` | 82 |
| Widgets / flujo de pantallas | `flutter_test` | `movil/test/widget` | 11 |
| Integración app ↔ servidor (Docker) | `flutter_test` + etiqueta `integration` | `movil/test/integration` | 8 |
| Punta a punta en emulador o celular | `integration_test` | `movil/integration_test` | 1 |
| Aceptación manual | Checklist (sección 6) | Equipo real | 8 |

## 3. Cómo ejecutar

```bash
make test                 # todo, en Docker (servidor + app + integración)
make test-servidor        # 85 pruebas del servidor
make test-movil           # flutter analyze + unitarias + widgets
make test-integracion     # app contra el servidor en Docker
```

Sin `make` (Windows):

```bash
docker compose up -d --build --wait db api
docker compose --profile test run --rm --build api-tests
docker compose --profile test run --rm --build movil-test
docker compose --profile test run --rm --build movil-integracion
```

Punta a punta (necesita emulador Android encendido y `make up`):

```bash
cd movil
bash tool/preparar_plataformas.sh
flutter test integration_test --dart-define-from-file=dart_defines.docker.json
```

Reportes que quedan en `reportes/`:
- `servidor/junit-unit.xml`, `servidor/junit-integracion.xml`
- `movil/flutter-unit.json`, `movil/lcov-movil.info` (cobertura), `movil/flutter-integracion.json`

## 4. Datos de prueba

Los carga `backend/db/03_semilla.sql`. Contraseña de todas las cuentas: `Stex2026!`

| Cuenta | Caso que cubre |
|---|---|
| `almacen1@apjltextil.com` | Operario del almacén Textiles del Norte (caso normal) |
| `almacen2@apjltextil.com` | Otro almacén (aislamiento) |
| `admin@apjltextil.com` | Admin: ve y sube cualquier almacén |
| `desactivado@apjltextil.com` | Perfil desactivado → 403 |
| `sinalmacen@apjltextil.com` | Sin almacén asignado → 403 |

PIN: Juan Carlos Pérez `1234`, María Torres `4321` (almacén 1); Pedro Ramos `1111` (almacén 2); Luis Inactivo `2222` (inactivo, no debe bajar).

## 5. Trazabilidad: requisito → pruebas

| Requisito | Criterio de aceptación | Pruebas automáticas |
|---|---|---|
| **v2 Paso 1** · Vincular una sola vez | Pide contraseña solo al instalar | `app_state_test`: *vincula, descarga maestros…*, *al reiniciar la app ya no pide la contraseña*; `flujo_app_test`: *credenciales incorrectas…* |
| **v2 Paso 2** · Descarga de maestros | Solo datos del almacén; sin PIN en claro | `sync-download.test`: *cuenta del almacén 1…*, *pin_hash correcto y el PIN no viaja*, *Admin*, *403 desactivada / sin almacén*; `sync_controller_test`: *descargarMaestros* (5 casos); `sync_servidor_test`: *download* |
| **v2 Paso 3 / HU-05** · Operario + PIN offline | Valida sin red; bloquea tras 5 fallos | `app_state_test`: grupo *PIN (paso 3, offline)* (4 casos); `flujo_app_test`: *PIN incorrecto…*; `pin_pad_test` (5 casos) |
| **v2 Paso 4** · Campaña | Libro ligado a campaña abierta | `repositorios_test`: *crear deja un libro abierto…*; `sync-download.test`: solo campañas abiertas |
| **v2 Paso 5 / HU-06** · Captura táctil | Botones ≥ 48 dp; registro inmediato; confirmación > 150 kg | `pin_pad_test`: *las teclas miden al menos 48 dp*; `flujo_app_test`: *flujo completo* (incluye confirmación de 200 kg); `repositorios_test`: *agregarMovimiento…*, *un registro inválido no deja nada escrito* |
| **HU-07** · Persistencia local | Registros sobreviven a cerrar la app / apagón | `app_state_test`: *los registros sobreviven a cerrar y reabrir la app*; `repositorios_test`: transacciones atómicas; manual A-3 y A-4 (apagón real) |
| **HU-08** · Pendientes de envío | Lista de libros no transmitidos | `repositorios_test`: *cerrar…cola de envío*, *contarSinEnviar*; `flujo_app_test`: *sin red…* (pendientes = 1) |
| **v2 Paso 6 / HU-09** · Envío al volver la red | Envía solo al reconectar; marca enviado tras 200 | `sync_controller_test`: *al recuperar la red envía automáticamente*, *envía los libros cerrados…*; `flujo_app_test`: *sin red: … se envía al volver la conexión*; `app_state_test`: *al arrancar con red envía lo pendiente* |
| Idempotencia (sin libros duplicados) | Reenvío no duplica | `sync-upload.test`: *reenviar el mismo libro*, *envíos simultáneos*; `sync_servidor_test`: *reenvío idempotente*; `servicio.test` |
| Atomicidad en el servidor | Error en un detalle → nada guardado | `sync-upload.test`: *422 y nada guardado si un material no existe* |
| Aislamiento por almacén | Operario no sube libros de otro almacén | `sync-upload.test`: *403 si la cuenta sube un libro de otro almacén*; `sync_servidor_test`: *libro de otro almacén → 403* |
| Sesión expirada | Renueva token; si no puede, pide contraseña sin perder datos | `api_client_test`: grupo *sesión* (5 casos); `sync_controller_test`: *sesión inválida…*; `app_state_test`: *reautenticar…* |
| Robustez de red | Sin red o 5xx se reintenta; 4xx no detiene la cola | `api_client_test`: grupo *errores*; `sync_controller_test`: *si se cae la red a mitad*, *un rechazo de negocio (403) no detiene el resto* |
| Seguridad del PIN | Hash idéntico en servidor y app | `core_test` y `jwt-pin.test` usan el mismo vector |
| Validación de entrada | Rechaza datos inválidos con mensaje claro | `validacion.test` (25 casos), `sync-upload.test` (validaciones 400) |
| Desvincular | Borra base, sesión y claves; avisa si hay pendientes | `app_state_test`: *desvincular borra base, sesión y claves*; `flujo_app_test`: *desvincular avisa…* |

## 6. Pruebas de aceptación manuales (equipo real)

| ID | Pasos | Resultado esperado |
|---|---|---|
| A-1 | Instalar el APK, vincular con `almacen1@…` | Aparece la lista de operarios |
| A-2 | Modo avión → PIN 1234 → crear libro → 5 registros → cerrar | Todo funciona sin red; banner naranja visible |
| A-3 | Registrar un ítem y, al ver "Registrado", forzar apagado (botón de encendido) | Al reiniciar, el ítem sigue en el libro |
| A-4 | Registrar, cerrar la app desde multitarea, reabrir | El libro abierto y sus ítems siguen ahí |
| A-5 | Con libros pendientes, quitar modo avión | Se envían solos en segundos; badge de Sync en 0 |
| A-6 | Enviar un libro y cortar la red justo después; reintentar | En el panel aparece un solo libro |
| A-7 | 5 PIN incorrectos | Bloqueo de 60 s |
| A-8 | Tablet en horizontal | Captura a la izquierda, registros a la derecha |

## 7. Criterios de salida

- 0 fallos en `make test`.
- `flutter analyze` sin errores ni advertencias (las sugerencias de estilo no bloquean).
- Cobertura de la lógica del servidor ≥ 90 % de líneas (medida: 97,9 %).
- Aceptación manual A-1 a A-7 aprobada en al menos un equipo Android.

## 8. Estado de la verificación

| Parte | Estado |
|---|---|
| Servidor: 85 pruebas (unitarias + integración) | ✅ Pasan localmente y dentro de Docker contra el contenedor `api` |
| Cobertura del servidor | ✅ 97,9 % líneas · 91,5 % ramas |
| Migración SQL en PostgreSQL 16 | ✅ Corre dos veces sin error; idempotencia y atomicidad verificadas |
| Pruebas de mutación (quitar aislamiento o idempotencia) | ✅ Las pruebas fallan como deben |
| Cliente oficial supabase-js contra el Auth local | ✅ login, getUser, refresh, signOut |
| Dockerfile del panel Next.js 16 con el parche | ✅ Construye, corre como `node`, queda healthy |
| docker-compose (db + api + api-tests) | ✅ Levanta en orden con healthchecks |
| App Flutter: analyze + 101 pruebas + integración | ⏳ Pendiente de la primera corrida en tu máquina (`make test-movil`, `make test-integracion`). Ver README, sección "Si algo falla". |

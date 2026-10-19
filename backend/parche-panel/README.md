# Parche del panel STEX-INV para la app móvil (sync v2.1)

## Qué copiar al proyecto `stex-inv` (Next.js)

```
lib/sync/contrato.ts      NUEVO  tipos y contrato
lib/sync/pin.ts           NUEVO  hash del PIN
lib/sync/validacion.ts    NUEVO  validación del libro
lib/sync/servicio.ts      NUEVO  reglas de download/upload
lib/sync/supabase.ts      NUEVO  autenticación Bearer + repositorio Supabase
app/api/sync/download/route.ts   REEMPLAZA
app/api/sync/upload/route.ts     REEMPLAZA
Dockerfile, .dockerignore        NUEVOS (imagen de producción)
supabase/migrations/20261018_sync_movil.sql   ejecutar en Supabase
```

Orden: primero el SQL y después el código. El SQL se puede correr varias veces y no borra nada. Para Docker agrega `output: "standalone"` en `next.config.ts`.

## Qué cambia

1. **La tablet recibía 401.** Las rutas leían la sesión desde cookies y la app manda `Authorization: Bearer <JWT>`. `lib/sync/supabase.ts` crea un cliente con ese token, así RLS sigue aplicándose.
2. **Operarios en la descarga**, con `pin_hash = sha256("<operario_id>:<pin>")`. El PIN no sale del servidor.
3. **Sin libros duplicados:** la app genera el `libro_id` y la función SQL responde `duplicado: true` si ya existía.
4. **Una sola transacción** para el libro y sus detalles (sin rollback manual).
5. **Trazabilidad:** `operario_id`, `fecha_conteo`, `fecha_cierre` y `origen` en `libros_conteo`; `operario_id` y `fecha_registro` en `movimientos_inventario`.
6. **Aislamiento:** una cuenta que no es Admin solo descarga y sube datos de su almacén.

## Supuestos sobre tu esquema (revisar)

- `materiales.estado`, `almacenes.estado` y `personal_planta.estado` son `boolean`.
- `campanas_inventario.estado` es texto con el valor `'Abierta'`.
- `libros_conteo.libro_id` es `uuid` y llave primaria.
- `usuarios_perfiles.usuario_id` es el id de Supabase Auth.
- Si tus tablas tienen RLS, el rol `authenticated` necesita permiso de INSERT en `libros_conteo` y `movimientos_inventario` para su almacén (la función usa `security invoker`).

## Contrato

**GET /api/sync/download** → `{ success, data: { campanas, almacenes, materiales, operarios[{…, pin_hash}] }, timestamp }`

**POST /api/sync/upload**

```json
{
  "libro_id": "uuid generado en la tablet",
  "campana_id": "uuid", "almacen_id": "uuid", "operario_id": "uuid",
  "fecha_conteo": "2026-10-18T19:00:00Z", "fecha_cierre": "2026-10-18T20:30:00Z",
  "detalles": [
    { "movimiento_id": "uuid", "material_id": "uuid", "cantidad_unidad": 45,
      "peso_neto": 112.75, "observacion": "Caja verde", "fecha_registro": "2026-10-18T19:05:00Z" }
  ]
}
```

Respuestas: `200 { success, message, libro_id, duplicado }` · `400` datos no válidos · `401` sesión · `403` otro almacén o cuenta desactivada · `422` campaña/almacén/material/operario inexistente · `500` error del servidor.

## Verificado

- `next build` con Next.js 16.3.8 y TypeScript estricto: compila.
- La imagen Docker construye, corre como usuario `node` y pasa el healthcheck.
- Las reglas de `lib/sync` tienen 85 pruebas (ver `backend/servidor-local`), con 100 % de cobertura en `servicio.ts` y `validacion.ts`.

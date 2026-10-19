import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { CORREO, ID, iniciarEntorno, libro, limpiar, login, pedir, type Entorno } from "./entorno";

let e: Entorno;
let token: string;

before(async () => {
  e = await iniciarEntorno();
});
beforeEach(async () => {
  await limpiar(e.pool);
  token = (await login(e.url, CORREO.almacen1)).access_token;
});
after(() => e.cerrar());

async function contar() {
  const l = await e.pool.query("select count(*)::int n from public.libros_conteo");
  const m = await e.pool.query("select count(*)::int n from public.movimientos_inventario");
  return { libros: l.rows[0].n as number, movimientos: m.rows[0].n as number };
}

const subir = (body: unknown, t = token) => pedir(e.url, "/api/sync/upload", { token: t, body });

describe("POST /api/sync/upload", () => {
  it("guarda el libro con trazabilidad completa", async () => {
    const r = await subir(libro());
    assert.equal(r.status, 200, r.texto);
    assert.equal(r.json.success, true);
    assert.equal(r.json.duplicado, false);
    assert.equal(r.json.libro_id, libro().libro_id);

    const l = await e.pool.query(
      `select usuario_id::text, operario_id::text, origen, estado_general,
              fecha_conteo, fecha_cierre from public.libros_conteo`,
    );
    assert.equal(l.rowCount, 1);
    assert.equal(l.rows[0].usuario_id, ID.usuarioAlmacen1);
    assert.equal(l.rows[0].operario_id, ID.juan);
    assert.equal(l.rows[0].origen, "movil");
    assert.equal(l.rows[0].estado_general, "Auditado");
    assert.equal(l.rows[0].fecha_conteo.toISOString(), "2026-10-18T19:00:00.000Z");

    const m = await e.pool.query(
      `select count(*)::int n, sum(peso_neto)::float total, bool_and(estado_sync = 'Sincronizado') sync,
              bool_and(operario_id = $1::uuid) op
         from public.movimientos_inventario`,
      [ID.juan],
    );
    assert.deepEqual(m.rows[0], { n: 2, total: 137.75, sync: true, op: true });
  });

  it("idempotencia: reenviar el mismo libro no lo duplica", async () => {
    assert.equal((await subir(libro())).json.duplicado, false);
    const r = await subir(libro());
    assert.equal(r.status, 200);
    assert.equal(r.json.duplicado, true);
    assert.match(r.json.message, /ya estaba registrado/);
    assert.deepEqual(await contar(), { libros: 1, movimientos: 2 });
  });

  it("idempotencia con envíos simultáneos del mismo libro", async () => {
    const respuestas = await Promise.all([subir(libro()), subir(libro()), subir(libro())]);
    assert.ok(respuestas.every((r) => r.status === 200));
    assert.equal(respuestas.filter((r) => r.json.duplicado === false).length, 1);
    assert.deepEqual(await contar(), { libros: 1, movimientos: 2 });
  });

  it("403 si la cuenta sube un libro de otro almacén", async () => {
    const r = await subir(libro({ almacen_id: ID.almacen2 }));
    assert.equal(r.status, 403);
    assert.deepEqual(await contar(), { libros: 0, movimientos: 0 });
  });

  it("un Admin puede subir libros de cualquier almacén", async () => {
    const admin = (await login(e.url, CORREO.admin)).access_token;
    const r = await subir(libro({ almacen_id: ID.almacen2, operario_id: ID.pedro }), admin);
    assert.equal(r.status, 200, r.texto);
  });

  it("403 para una cuenta desactivada", async () => {
    const t = (await login(e.url, CORREO.desactivado)).access_token;
    assert.equal((await subir(libro(), t)).status, 403);
  });

  it("401 sin token", async () => {
    const r = await pedir(e.url, "/api/sync/upload", { body: libro() });
    assert.equal(r.status, 401);
  });

  it("400 con JSON inválido", async () => {
    const r = await pedir(e.url, "/api/sync/upload", { token, crudo: "{no es json" });
    assert.equal(r.status, 400);
    assert.equal(r.json.message, "JSON inválido.");
  });

  for (const [nombre, body, mensaje] of [
    ["sin detalles", libro({ detalles: [] }), /al menos un detalle/],
    ["peso negativo", libro({ detalles: [{ material_id: ID.hilo, cantidad_unidad: 1, peso_neto: -5 }] }), /peso_neto/],
    ["campaña inválida", libro({ campana_id: "octubre" }), /campana_id/],
  ] as const) {
    it(`400 por validación: ${nombre}`, async () => {
      const r = await subir(body);
      assert.equal(r.status, 400);
      assert.match(r.json.message, mensaje);
      assert.deepEqual(await contar(), { libros: 0, movimientos: 0 });
    });
  }

  it("422 y nada guardado si un material no existe (transacción atómica)", async () => {
    const body = libro();
    body.detalles.push({
      movimiento_id: "f1000000-0000-4000-8000-000000000003",
      material_id: "b1000000-0000-4000-8000-0000000000ff",
      cantidad_unidad: 1,
      peso_neto: 1,
      observacion: null,
      fecha_registro: "2026-10-18T19:20:00Z",
    });
    const r = await subir(body);
    assert.equal(r.status, 422);
    assert.match(r.json.message, /Actualiza los datos maestros/);
    assert.deepEqual(await contar(), { libros: 0, movimientos: 0 });
  });

  it("422 si el operario no existe", async () => {
    const r = await subir(libro({ operario_id: "d1000000-0000-4000-8000-0000000000ff" }));
    assert.equal(r.status, 422);
  });

  it("acepta clientes antiguos sin libro_id ni operario_id", async () => {
    const body = libro();
    delete (body as Record<string, unknown>).libro_id;
    delete (body as Record<string, unknown>).operario_id;
    const r = await subir(body);
    assert.equal(r.status, 200, r.texto);
    assert.match(r.json.libro_id, /^[0-9a-f-]{36}$/);
    assert.notEqual(r.json.libro_id, libro().libro_id);
  });
});

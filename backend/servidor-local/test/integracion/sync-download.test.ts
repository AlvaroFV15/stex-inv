import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { hashPin } from "../../../parche-panel/lib/sync/pin";
import { CORREO, ID, iniciarEntorno, limpiar, login, pedir, tokenManual, type Entorno } from "./entorno";

let e: Entorno;
before(async () => {
  e = await iniciarEntorno();
  await limpiar(e.pool);
});
after(() => e.cerrar());

const ids = (lista: Array<Record<string, string>>, campo: string) => lista.map((x) => x[campo]).sort();

describe("GET /api/sync/download", () => {
  it("401 sin token", async () => {
    const r = await pedir(e.url, "/api/sync/download");
    assert.equal(r.status, 401);
    assert.equal(r.json.success, false);
  });

  it("401 con token mal formado", async () => {
    assert.equal((await pedir(e.url, "/api/sync/download", { token: "abc" })).status, 401);
  });

  it("401 con token expirado", async () => {
    const t = tokenManual(e.secreto, ID.usuarioAlmacen1, -60);
    assert.equal((await pedir(e.url, "/api/sync/download", { token: t })).status, 401);
  });

  it("401 con token de un usuario que ya no existe", async () => {
    const t = tokenManual(e.secreto, "e1000000-0000-4000-8000-0000000000ff", 600);
    assert.equal((await pedir(e.url, "/api/sync/download", { token: t })).status, 401);
  });

  it("cuenta del almacén 1: solo su almacén, sus operarios activos y materiales activos", async () => {
    const s = await login(e.url, CORREO.almacen1);
    const r = await pedir(e.url, "/api/sync/download", { token: s.access_token });
    assert.equal(r.status, 200);
    assert.equal(r.json.success, true);
    const d = r.json.data;

    assert.deepEqual(ids(d.almacenes, "almacen_id"), [ID.almacen1]);
    assert.deepEqual(ids(d.operarios, "operario_id"), [ID.juan, ID.maria].sort());
    assert.deepEqual(ids(d.materiales, "material_id"), [ID.hilo, ID.jersey, ID.poliester].sort());
    assert.deepEqual(ids(d.campanas, "campana_id"), [ID.campanaAbierta]);

    const campana = d.campanas[0];
    assert.equal(campana.fecha_inicio, "2026-10-01");
    assert.equal(campana.fecha_fin, "2026-10-31");
    assert.ok(!Number.isNaN(Date.parse(r.json.timestamp)));
  });

  it("los operarios llevan pin_hash correcto y el PIN no viaja", async () => {
    const s = await login(e.url, CORREO.almacen1);
    const r = await pedir(e.url, "/api/sync/download", { token: s.access_token });
    const juan = r.json.data.operarios.find((o: any) => o.operario_id === ID.juan);
    assert.equal(juan.pin_hash, hashPin(ID.juan, "1234"));
    assert.equal(juan.nombre_completo, "Juan Carlos Pérez");
    assert.equal(r.texto.includes("pin_seguridad"), false);
    assert.equal(r.texto.includes('"1234"'), false);
  });

  it("cuenta Admin: todos los almacenes y operarios activos", async () => {
    const s = await login(e.url, CORREO.admin);
    const r = await pedir(e.url, "/api/sync/download", { token: s.access_token });
    assert.equal(r.status, 200);
    assert.deepEqual(ids(r.json.data.almacenes, "almacen_id"), [ID.almacen1, ID.almacen2].sort());
    assert.deepEqual(ids(r.json.data.operarios, "operario_id"), [ID.juan, ID.maria, ID.pedro].sort());
  });

  it("403 para una cuenta desactivada", async () => {
    const s = await login(e.url, CORREO.desactivado);
    const r = await pedir(e.url, "/api/sync/download", { token: s.access_token });
    assert.equal(r.status, 403);
    assert.match(r.json.message, /desactivada/);
  });

  it("403 para una cuenta sin almacén asignado", async () => {
    const s = await login(e.url, CORREO.sinAlmacen);
    const r = await pedir(e.url, "/api/sync/download", { token: s.access_token });
    assert.equal(r.status, 403);
    assert.match(r.json.message, /almacén asignado/);
  });
});

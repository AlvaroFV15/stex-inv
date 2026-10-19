import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  ErrorRepositorio,
  type LibroPayload,
  type OperarioFila,
  type RepositorioSync,
  type ResultadoRegistro,
  type Sesion,
} from "../../../parche-panel/lib/sync/contrato";
import { hashPin } from "../../../parche-panel/lib/sync/pin";
import { descargarMaestros, subirLibro } from "../../../parche-panel/lib/sync/servicio";

const A1 = "a1000000-0000-4000-8000-000000000001";
const A2 = "a1000000-0000-4000-8000-000000000002";

class RepoFalso implements RepositorioSync {
  almacenPedido: string | null | undefined;
  operariosPedido: string | null | undefined;
  registrados: LibroPayload[] = [];
  errorRegistro: Error | null = null;
  errorLectura: Error | null = null;
  operarios: OperarioFila[] = [
    { operario_id: "o1", nombre_completo: "Juan", pin_seguridad: "1234", almacen_id: A1 },
    { operario_id: "o2", nombre_completo: "Sin PIN", pin_seguridad: null, almacen_id: A1 },
  ];

  async campanasAbiertas() {
    if (this.errorLectura) throw this.errorLectura;
    return [{ campanas_id: "c1", nombre: "Octubre", fecha_inicio: "2026-10-01", fecha_fin: "2026-10-31" }];
  }
  async almacenesActivos(id: string | null) {
    this.almacenPedido = id;
    return [{ almacen_id: A1, codigo_almacen: "TEJ04", nro_almacen: "9", razon_social: "Textiles", nombre_local: null }];
  }
  async materialesActivos() {
    return [{ material_id: "m1", codigo_material: "MAT-001", kardex_numero: "1001", descripcion: "Hilo" }];
  }
  async operariosActivos(id: string | null) {
    this.operariosPedido = id;
    return this.operarios;
  }
  async registrarLibro(p: LibroPayload): Promise<ResultadoRegistro> {
    if (this.errorRegistro) throw this.errorRegistro;
    const duplicado = this.registrados.some((r) => r.libro_id === p.libro_id);
    if (!duplicado) this.registrados.push(p);
    return { libro_id: p.libro_id, duplicado };
  }
}

const operario: Sesion = { usuarioId: "u1", perfil: { rol: "Operario", almacen_id: A1, estado: true } };
const admin: Sesion = { usuarioId: "u2", perfil: { rol: "Admin", almacen_id: null, estado: true } };
const desactivado: Sesion = { usuarioId: "u3", perfil: { rol: "Operario", almacen_id: A1, estado: false } };
const sinAlmacen: Sesion = { usuarioId: "u4", perfil: { rol: "Operario", almacen_id: null, estado: true } };
const sinPerfil: Sesion = { usuarioId: "u5", perfil: null };

const libro = (almacen = A1) => ({
  libro_id: "9b8a7c6d-5e4f-4a2b-9c0d-9e8f7a6b5c4d",
  campana_id: "c1000000-0000-4000-8000-000000000001",
  almacen_id: almacen,
  detalles: [{ material_id: "b1000000-0000-4000-8000-000000000001", cantidad_unidad: 1, peso_neto: 2 }],
});

describe("descargarMaestros", () => {
  it("cuenta Operario: filtra por su almacén y envía pin_hash, nunca el PIN", async () => {
    const repo = new RepoFalso();
    const r = await descargarMaestros(operario, repo, { ahora: () => new Date("2026-10-19T00:00:00Z") });
    assert.equal(r.status, 200);
    assert.equal(repo.almacenPedido, A1);
    assert.equal(repo.operariosPedido, A1);
    const data = r.body.data as { operarios: Record<string, unknown>[]; campanas: Record<string, unknown>[] };
    assert.deepEqual(data.operarios, [
      { operario_id: "o1", nombre_completo: "Juan", almacen_id: A1, pin_hash: hashPin("o1", "1234") },
    ]);
    assert.equal(JSON.stringify(r.body).includes("pin_seguridad"), false);
    assert.equal(JSON.stringify(r.body).includes('"1234"'), false);
    assert.equal(data.campanas[0]!.campana_id, "c1");
    assert.equal(r.body.timestamp, "2026-10-19T00:00:00.000Z");
  });

  it("cuenta Admin: pide todos los almacenes y operarios", async () => {
    const repo = new RepoFalso();
    const r = await descargarMaestros(admin, repo);
    assert.equal(r.status, 200);
    assert.equal(repo.almacenPedido, null);
    assert.equal(repo.operariosPedido, null);
  });

  for (const [nombre, sesion, mensaje] of [
    ["cuenta desactivada", desactivado, /desactivada/],
    ["cuenta sin almacén", sinAlmacen, /almacén asignado/],
    ["usuario sin perfil", sinPerfil, /almacén asignado/],
  ] as const) {
    it(`403 para ${nombre}`, async () => {
      const r = await descargarMaestros(sesion, new RepoFalso());
      assert.equal(r.status, 403);
      assert.match(String(r.body.message), mensaje);
    });
  }

  it("500 si falla la base, sin exponer el detalle", async () => {
    const repo = new RepoFalso();
    repo.errorLectura = new Error("connection refused 10.0.0.5");
    const errores: unknown[] = [];
    const r = await descargarMaestros(operario, repo, { registro: { error: (...a) => errores.push(a) } });
    assert.equal(r.status, 500);
    assert.equal(JSON.stringify(r.body).includes("10.0.0.5"), false);
    assert.equal(errores.length, 1);
  });
});

describe("subirLibro", () => {
  it("guarda y luego detecta el reenvío como duplicado", async () => {
    const repo = new RepoFalso();
    const r1 = await subirLibro(operario, repo, libro());
    const r2 = await subirLibro(operario, repo, libro());
    assert.equal(r1.status, 200);
    assert.equal(r1.body.duplicado, false);
    assert.equal(r2.status, 200);
    assert.equal(r2.body.duplicado, true);
    assert.equal(repo.registrados.length, 1);
  });

  it("400 con el mensaje de validación", async () => {
    const r = await subirLibro(operario, new RepoFalso(), { ...libro(), detalles: [] });
    assert.equal(r.status, 400);
    assert.match(String(r.body.message), /al menos un detalle/);
  });

  it("403 si un Operario sube un libro de otro almacén", async () => {
    const repo = new RepoFalso();
    const r = await subirLibro(operario, repo, libro(A2));
    assert.equal(r.status, 403);
    assert.equal(repo.registrados.length, 0);
  });

  it("un Admin puede subir libros de cualquier almacén", async () => {
    const r = await subirLibro(admin, new RepoFalso(), libro(A2));
    assert.equal(r.status, 200);
  });

  it("403 si la cuenta está desactivada", async () => {
    const r = await subirLibro(desactivado, new RepoFalso(), libro());
    assert.equal(r.status, 403);
  });

  const errores: Array<[string | undefined, number]> = [
    ["23503", 422],
    ["22023", 400],
    ["22P02", 400],
    ["22003", 400],
    ["23514", 400],
    ["28000", 401],
    ["XX000", 500],
    [undefined, 500],
  ];
  for (const [codigo, status] of errores) {
    it(`traduce el error de base ${codigo ?? "(sin código)"} a ${status}`, async () => {
      const repo = new RepoFalso();
      repo.errorRegistro = codigo ? new ErrorRepositorio("fallo", codigo) : new Error("fallo");
      const r = await subirLibro(operario, repo, libro());
      assert.equal(r.status, status);
      assert.equal(r.body.success, false);
    });
  }
});

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { MAX_DETALLES, validarLibro } from "../../../parche-panel/lib/sync/validacion";

const ID = {
  libro: "9b8a7c6d-5e4f-4a2b-9c0d-9e8f7a6b5c4d",
  campana: "c1000000-0000-4000-8000-000000000001",
  almacen: "a1000000-0000-4000-8000-000000000001",
  material: "b1000000-0000-4000-8000-000000000001",
  operario: "d1000000-0000-4000-8000-000000000001",
};

const detalle = (extra: Record<string, unknown> = {}) => ({
  material_id: ID.material,
  cantidad_unidad: 45,
  peso_neto: 112.75,
  observacion: "Conos en caja verde",
  ...extra,
});

const libro = (extra: Record<string, unknown> = {}) => ({
  libro_id: ID.libro,
  campana_id: ID.campana,
  almacen_id: ID.almacen,
  operario_id: ID.operario,
  fecha_conteo: "2026-10-18T19:00:00Z",
  fecha_cierre: "2026-10-18T20:30:00Z",
  detalles: [detalle()],
  ...extra,
});

describe("validarLibro", () => {
  it("acepta un libro válido y lo normaliza", () => {
    const r = validarLibro(libro());
    assert.notEqual(typeof r, "string");
    assert.deepEqual(r, {
      libro_id: ID.libro,
      campana_id: ID.campana,
      almacen_id: ID.almacen,
      operario_id: ID.operario,
      fecha_conteo: "2026-10-18T19:00:00Z",
      fecha_cierre: "2026-10-18T20:30:00Z",
      detalles: [
        {
          material_id: ID.material,
          cantidad_unidad: 45,
          peso_neto: 112.75,
          observacion: "Conos en caja verde",
          fecha_registro: null,
        },
      ],
    });
  });

  it("genera libro_id si un cliente antiguo no lo envía", () => {
    const r = validarLibro(libro({ libro_id: undefined }), () => "11111111-1111-4111-8111-111111111111");
    assert.equal(typeof r === "string" ? r : r.libro_id, "11111111-1111-4111-8111-111111111111");
  });

  it("acepta cantidad y peso en cero (stock vacío)", () => {
    assert.notEqual(typeof validarLibro(libro({ detalles: [detalle({ cantidad_unidad: 0, peso_neto: 0 })] })), "string");
  });

  it("descarta fechas que no se pueden interpretar", () => {
    const r = validarLibro(libro({ fecha_conteo: "ayer" }));
    assert.equal(typeof r === "string" ? r : r.fecha_conteo, null);
  });

  const invalidos: Array<[string, unknown, RegExp]> = [
    ["cuerpo nulo", null, /objeto JSON/],
    ["cuerpo arreglo", [], /objeto JSON/],
    ["campana_id inválido", libro({ campana_id: "x" }), /campana_id/],
    ["almacen_id faltante", libro({ almacen_id: undefined }), /almacen_id/],
    ["libro_id inválido", libro({ libro_id: 123 }), /libro_id/],
    ["operario_id inválido", libro({ operario_id: "juan" }), /operario_id/],
    ["sin detalles", libro({ detalles: [] }), /al menos un detalle/],
    ["detalles no arreglo", libro({ detalles: "x" }), /al menos un detalle/],
    ["demasiados detalles", libro({ detalles: Array(MAX_DETALLES + 1).fill(detalle()) }), /Máximo/],
    ["detalle no objeto", libro({ detalles: [1] }), /Detalle 1: debe ser un objeto/],
    ["material inválido", libro({ detalles: [detalle({ material_id: "m" })] }), /Detalle 1: material_id/],
    ["cantidad decimal", libro({ detalles: [detalle({ cantidad_unidad: 1.5 })] }), /cantidad_unidad/],
    ["cantidad negativa", libro({ detalles: [detalle({ cantidad_unidad: -1 })] }), /cantidad_unidad/],
    ["cantidad texto", libro({ detalles: [detalle({ cantidad_unidad: "4" })] }), /cantidad_unidad/],
    ["peso negativo", libro({ detalles: [detalle({ peso_neto: -0.1 })] }), /peso_neto/],
    ["peso infinito", libro({ detalles: [detalle({ peso_neto: Infinity })] }), /peso_neto/],
    ["peso excesivo", libro({ detalles: [detalle({ peso_neto: 2_000_000 })] }), /peso_neto/],
    ["observación larga", libro({ detalles: [detalle({ observacion: "x".repeat(501) })] }), /observacion/],
    ["observación no texto", libro({ detalles: [detalle({ observacion: 5 })] }), /observacion/],
    ["movimiento_id inválido", libro({ detalles: [detalle({ movimiento_id: "z" })] }), /movimiento_id/],
    ["segundo detalle con error", libro({ detalles: [detalle(), detalle({ peso_neto: -1 })] }), /Detalle 2/],
  ];

  for (const [nombre, body, mensaje] of invalidos) {
    it(`rechaza: ${nombre}`, () => {
      const r = validarLibro(body);
      assert.equal(typeof r, "string");
      assert.match(r as string, mensaje);
    });
  }
});

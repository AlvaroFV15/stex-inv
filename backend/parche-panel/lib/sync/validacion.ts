import { randomUUID } from "node:crypto";

import type { DetalleLibro, LibroPayload } from "./contrato";

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const MAX_DETALLES = 5000;
export const MAX_OBSERVACION = 500;
export const MAX_CANTIDAD = 2_147_483_647;
export const MAX_PESO_KG = 1_000_000;

const esUuid = (v: unknown): v is string => typeof v === "string" && UUID.test(v);
const esFecha = (v: unknown): v is string =>
  typeof v === "string" && !Number.isNaN(Date.parse(v));

/**
 * Valida y normaliza el cuerpo de POST /api/sync/upload.
 * Devuelve el payload listo para guardar o un mensaje de error en español.
 *
 * @param generarId se usa solo si un cliente antiguo no envía `libro_id`.
 */
export function validarLibro(
  body: unknown,
  generarId: () => string = randomUUID,
): LibroPayload | string {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return "El cuerpo debe ser un objeto JSON.";
  }
  const b = body as Record<string, unknown>;

  if (!esUuid(b.campana_id)) return "campana_id no es un UUID válido.";
  if (!esUuid(b.almacen_id)) return "almacen_id no es un UUID válido.";

  // Compatibilidad: clientes antiguos no mandan libro_id (sin idempotencia).
  const libroId = b.libro_id === undefined || b.libro_id === null ? generarId() : b.libro_id;
  if (!esUuid(libroId)) return "libro_id no es un UUID válido.";

  if (b.operario_id != null && !esUuid(b.operario_id)) {
    return "operario_id no es un UUID válido.";
  }

  if (!Array.isArray(b.detalles) || b.detalles.length === 0) {
    return "El libro debe tener al menos un detalle.";
  }
  if (b.detalles.length > MAX_DETALLES) {
    return `Máximo ${MAX_DETALLES} detalles por libro.`;
  }

  const detalles: DetalleLibro[] = [];
  for (const [i, raw] of b.detalles.entries()) {
    const n = i + 1;
    if (!raw || typeof raw !== "object") return `Detalle ${n}: debe ser un objeto.`;
    const d = raw as Record<string, unknown>;

    if (!esUuid(d.material_id)) return `Detalle ${n}: material_id no válido.`;
    if (
      typeof d.cantidad_unidad !== "number" ||
      !Number.isInteger(d.cantidad_unidad) ||
      d.cantidad_unidad < 0 ||
      d.cantidad_unidad > MAX_CANTIDAD
    ) {
      return `Detalle ${n}: cantidad_unidad debe ser un entero mayor o igual a 0.`;
    }
    if (
      typeof d.peso_neto !== "number" ||
      !Number.isFinite(d.peso_neto) ||
      d.peso_neto < 0 ||
      d.peso_neto > MAX_PESO_KG
    ) {
      return `Detalle ${n}: peso_neto debe ser un número entre 0 y ${MAX_PESO_KG}.`;
    }
    if (
      d.observacion != null &&
      (typeof d.observacion !== "string" || d.observacion.length > MAX_OBSERVACION)
    ) {
      return `Detalle ${n}: observacion debe ser texto de hasta ${MAX_OBSERVACION} caracteres.`;
    }
    if (d.movimiento_id != null && !esUuid(d.movimiento_id)) {
      return `Detalle ${n}: movimiento_id no válido.`;
    }

    detalles.push({
      material_id: d.material_id,
      cantidad_unidad: d.cantidad_unidad,
      peso_neto: d.peso_neto,
      observacion: typeof d.observacion === "string" ? d.observacion : null,
      fecha_registro: esFecha(d.fecha_registro) ? d.fecha_registro : null,
    });
  }

  return {
    libro_id: libroId,
    campana_id: b.campana_id,
    almacen_id: b.almacen_id,
    operario_id: typeof b.operario_id === "string" ? b.operario_id : null,
    fecha_conteo: esFecha(b.fecha_conteo) ? b.fecha_conteo : null,
    fecha_cierre: esFecha(b.fecha_cierre) ? b.fecha_cierre : null,
    detalles,
  };
}

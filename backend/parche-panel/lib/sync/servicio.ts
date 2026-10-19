import { randomUUID } from "node:crypto";

import {
  ErrorRepositorio,
  type Registro,
  type RepositorioSync,
  type Respuesta,
  type Sesion,
} from "./contrato";
import { hashPin } from "./pin";
import { validarLibro } from "./validacion";

/**
 * Reglas de negocio de /api/sync/download y /api/sync/upload.
 * No conocen HTTP ni Supabase: reciben la sesión ya autenticada y un
 * repositorio, y devuelven { status, body }.
 */

export type Opciones = {
  registro?: Registro;
  ahora?: () => Date;
  generarId?: () => string;
};

const silencioso: Registro = { error: () => {} };

const fallo = (status: number, message: string): Respuesta => ({
  status,
  body: { success: false, message },
});

const esAdmin = (s: Sesion) => s.perfil?.rol === "Admin";

/** 403 si el perfil del usuario está desactivado en el panel. */
export function verificarCuenta(sesion: Sesion): Respuesta | null {
  if (sesion.perfil && sesion.perfil.estado === false) {
    return fallo(403, "La cuenta está desactivada.");
  }
  return null;
}

/**
 * GET /api/sync/download
 *  - Cuenta Operario: solo su almacén y sus operarios.
 *  - Cuenta Admin: todos los almacenes y operarios activos.
 *  - El PIN nunca sale del servidor: se envía `pin_hash`.
 */
export async function descargarMaestros(
  sesion: Sesion,
  repo: RepositorioSync,
  opciones: Opciones = {},
): Promise<Respuesta> {
  const registro = opciones.registro ?? silencioso;
  const ahora = opciones.ahora ?? (() => new Date());

  const bloqueo = verificarCuenta(sesion);
  if (bloqueo) return bloqueo;

  const admin = esAdmin(sesion);
  const almacenId = admin ? null : (sesion.perfil?.almacen_id ?? null);
  if (!admin && !almacenId) {
    return fallo(403, "La cuenta no tiene un almacén asignado en el panel.");
  }

  try {
    const [campanas, almacenes, materiales, operarios] = await Promise.all([
      repo.campanasAbiertas(),
      repo.almacenesActivos(almacenId),
      repo.materialesActivos(),
      repo.operariosActivos(almacenId),
    ]);

    return {
      status: 200,
      body: {
        success: true,
        data: {
          campanas: campanas.map((c) => ({
            campana_id: c.campanas_id,
            nombre: c.nombre,
            fecha_inicio: c.fecha_inicio,
            fecha_fin: c.fecha_fin,
          })),
          almacenes,
          materiales,
          operarios: operarios
            .filter((o) => typeof o.pin_seguridad === "string" && o.pin_seguridad !== "")
            .map((o) => ({
              operario_id: o.operario_id,
              nombre_completo: o.nombre_completo,
              almacen_id: o.almacen_id,
              pin_hash: hashPin(o.operario_id, String(o.pin_seguridad)),
            })),
        },
        timestamp: ahora().toISOString(),
      },
    };
  } catch (e) {
    registro.error("[sync/download]", e);
    return fallo(500, "No se pudieron leer los datos maestros.");
  }
}

/**
 * POST /api/sync/upload
 *  - Valida el cuerpo.
 *  - Cuenta Operario: solo libros de su almacén.
 *  - Idempotente por libro_id (un reenvío responde duplicado: true).
 */
export async function subirLibro(
  sesion: Sesion,
  repo: RepositorioSync,
  body: unknown,
  opciones: Opciones = {},
): Promise<Respuesta> {
  const registro = opciones.registro ?? silencioso;

  const bloqueo = verificarCuenta(sesion);
  if (bloqueo) return bloqueo;

  const payload = validarLibro(body, opciones.generarId ?? randomUUID);
  if (typeof payload === "string") return fallo(400, payload);

  if (!esAdmin(sesion) && sesion.perfil?.almacen_id !== payload.almacen_id) {
    return fallo(403, "La cuenta no puede registrar libros de otro almacén.");
  }

  try {
    const r = await repo.registrarLibro(payload);
    return {
      status: 200,
      body: {
        success: true,
        message: r.duplicado
          ? "El libro ya estaba registrado."
          : "Libro de conteo guardado con éxito.",
        libro_id: r.libro_id,
        duplicado: r.duplicado,
      },
    };
  } catch (e) {
    const codigo = e instanceof ErrorRepositorio ? e.codigo : undefined;
    switch (codigo) {
      case "23503": // llave foránea
        return fallo(
          422,
          "El libro hace referencia a una campaña, almacén, material u operario que no existe. " +
            "Actualiza los datos maestros en la tablet.",
        );
      case "22023": // parámetro inválido (lanzado por la función SQL)
      case "22P02": // texto con formato inválido
      case "22003": // número fuera de rango
      case "23514": // restricción CHECK
        return fallo(400, "Datos del libro no válidos.");
      case "28000":
        return fallo(401, "Sesión no válida o expirada.");
      default:
        registro.error("[sync/upload]", e);
        return fallo(500, "No se pudo guardar el libro.");
    }
  }
}

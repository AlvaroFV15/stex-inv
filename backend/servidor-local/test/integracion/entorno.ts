import type { AddressInfo } from "node:net";

import { Pool } from "pg";

import { leerConfig } from "../../src/config";
import { firmarJwt } from "../../src/jwt";
import { crearServidor } from "../../src/servidor";

/**
 * Entorno de las pruebas de integración.
 *  - Con STEX_API_URL: prueba un servidor ya levantado (contenedor `api`).
 *  - Sin STEX_API_URL: levanta el servidor en este proceso (puerto libre).
 * En ambos casos necesita DATABASE_URL con el esquema y la semilla cargados.
 */

export const SECRETO_POR_DEFECTO = "stex-local-jwt-secret-solo-para-pruebas-0123456789";
export const PASSWORD = "Stex2026!";

export const ID = {
  almacen1: "a1000000-0000-4000-8000-000000000001",
  almacen2: "a1000000-0000-4000-8000-000000000002",
  almacenInactivo: "a1000000-0000-4000-8000-000000000003",
  campanaAbierta: "c1000000-0000-4000-8000-000000000001",
  campanaCerrada: "c1000000-0000-4000-8000-000000000002",
  hilo: "b1000000-0000-4000-8000-000000000001",
  jersey: "b1000000-0000-4000-8000-000000000002",
  poliester: "b1000000-0000-4000-8000-000000000003",
  materialInactivo: "b1000000-0000-4000-8000-000000000004",
  juan: "d1000000-0000-4000-8000-000000000001",
  maria: "d1000000-0000-4000-8000-000000000002",
  pedro: "d1000000-0000-4000-8000-000000000003",
  luisInactivo: "d1000000-0000-4000-8000-000000000004",
  usuarioAlmacen1: "e1000000-0000-4000-8000-000000000001",
};

export const CORREO = {
  almacen1: "almacen1@apjltextil.com",
  almacen2: "almacen2@apjltextil.com",
  admin: "admin@apjltextil.com",
  desactivado: "desactivado@apjltextil.com",
  sinAlmacen: "sinalmacen@apjltextil.com",
};

export type Entorno = {
  url: string;
  pool: Pool;
  secreto: string;
  cerrar(): Promise<void>;
};

export async function iniciarEntorno(): Promise<Entorno> {
  const config = leerConfig({
    ...process.env,
    JWT_SECRET: process.env.JWT_SECRET ?? SECRETO_POR_DEFECTO,
  });
  const pool = new Pool({ connectionString: config.databaseUrl, max: 5 });

  const externo = process.env.STEX_API_URL;
  if (externo) {
    return { url: externo.replace(/\/$/, ""), pool, secreto: config.jwtSecreto, cerrar: () => pool.end() };
  }

  const servidor = crearServidor(pool, config, { info: () => {}, error: () => {} });
  await new Promise<void>((r) => servidor.listen(0, "127.0.0.1", r));
  const { port } = servidor.address() as AddressInfo;
  return {
    url: `http://127.0.0.1:${port}`,
    pool,
    secreto: config.jwtSecreto,
    cerrar: async () => {
      servidor.closeAllConnections();
      await new Promise((r) => servidor.close(r));
      await pool.end();
    },
  };
}

/** Deja la base como recién sembrada (sin libros ni sesiones). */
export async function limpiar(pool: Pool) {
  await pool.query("delete from public.movimientos_inventario");
  await pool.query("delete from public.libros_conteo");
  await pool.query("delete from auth.refresh_tokens");
}

export type Resultado = { status: number; json: any; texto: string };

export async function pedir(
  url: string,
  ruta: string,
  opciones: { metodo?: string; token?: string; body?: unknown; crudo?: string } = {},
): Promise<Resultado> {
  const headers: Record<string, string> = { "Content-Type": "application/json", apikey: "local-anon-key" };
  if (opciones.token) headers.Authorization = `Bearer ${opciones.token}`;
  const r = await fetch(`${url}${ruta}`, {
    method: opciones.metodo ?? (opciones.body !== undefined || opciones.crudo ? "POST" : "GET"),
    headers,
    body: opciones.crudo ?? (opciones.body === undefined ? undefined : JSON.stringify(opciones.body)),
  });
  const texto = await r.text();
  let json: any = null;
  try {
    json = texto ? JSON.parse(texto) : null;
  } catch {
    json = null;
  }
  return { status: r.status, json, texto };
}

export async function login(url: string, correo: string, password = PASSWORD) {
  const r = await pedir(url, "/auth/v1/token?grant_type=password", { body: { email: correo, password } });
  if (r.status !== 200) throw new Error(`login ${correo} falló: ${r.status} ${r.texto}`);
  return r.json as { access_token: string; refresh_token: string; user: { id: string } };
}

/** Token firmado a mano (para probar expiración o usuarios inexistentes). */
export function tokenManual(secreto: string, sub: string, expDesdeAhora: number) {
  const ahora = Math.floor(Date.now() / 1000);
  return firmarJwt(
    { sub, role: "authenticated", aud: "authenticated", iat: ahora - 10, exp: ahora + expDesdeAhora },
    secreto,
  );
}

export function libro(extra: Record<string, unknown> = {}) {
  return {
    libro_id: "9b8a7c6d-5e4f-4a2b-9c0d-9e8f7a6b5c4d",
    campana_id: ID.campanaAbierta,
    almacen_id: ID.almacen1,
    operario_id: ID.juan,
    fecha_conteo: "2026-10-18T19:00:00Z",
    fecha_cierre: "2026-10-18T20:30:00Z",
    detalles: [
      { movimiento_id: "f1000000-0000-4000-8000-000000000001", material_id: ID.hilo, cantidad_unidad: 45, peso_neto: 112.75, observacion: "Caja verde", fecha_registro: "2026-10-18T19:05:00Z" },
      { movimiento_id: "f1000000-0000-4000-8000-000000000002", material_id: ID.jersey, cantidad_unidad: 10, peso_neto: 25, observacion: null, fecha_registro: "2026-10-18T19:10:00Z" },
    ],
    ...extra,
  };
}

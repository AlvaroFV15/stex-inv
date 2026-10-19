import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";

import type { Pool } from "pg";

import type { Perfil, Respuesta, Sesion } from "../../parche-panel/lib/sync/contrato";
import { descargarMaestros, subirLibro } from "../../parche-panel/lib/sync/servicio";
import { ServicioAuth } from "./auth";
import type { Config } from "./config";
import { RepositorioPg } from "./repositorio-pg";

const MAX_CUERPO = 10 * 1024 * 1024;

class CuerpoDemasiadoGrande extends Error {}

function enviar(res: ServerResponse, status: number, body: unknown) {
  if (body === null || status === 204) {
    res.writeHead(status, { "Cache-Control": "no-store" }).end();
    return;
  }
  const texto = JSON.stringify(body);
  res
    .writeHead(status, {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Length": Buffer.byteLength(texto),
      "Cache-Control": "no-store",
    })
    .end(texto);
}

async function leerCuerpo(req: IncomingMessage): Promise<string> {
  const partes: Buffer[] = [];
  let total = 0;
  for await (const parte of req) {
    total += (parte as Buffer).length;
    if (total > MAX_CUERPO) throw new CuerpoDemasiadoGrande();
    partes.push(parte as Buffer);
  }
  return Buffer.concat(partes).toString("utf8");
}

function tokenBearer(req: IncomingMessage): string {
  const h = req.headers.authorization ?? "";
  return /^bearer /i.test(h) ? h.slice(7).trim() : "";
}

export type Registro = {
  info(mensaje: string): void;
  error(mensaje: string, detalle?: unknown): void;
};

export function crearServidor(pool: Pool, config: Config, registro: Registro = console): Server {
  const auth = new ServicioAuth(pool, config.jwtSecreto, config.jwtExpiraSegundos);

  /** Igual que el adaptador Supabase del panel: token → usuario → perfil. */
  async function sesionDe(req: IncomingMessage): Promise<Sesion | Respuesta> {
    const token = tokenBearer(req);
    if (!token) {
      return { status: 401, body: { success: false, message: "Falta el token de autorización." } };
    }
    const usuarioId = await auth.usuarioDelToken(token);
    if (!usuarioId) {
      return { status: 401, body: { success: false, message: "Sesión no válida o expirada." } };
    }
    const r = await pool.query<Perfil>(
      "select rol, almacen_id::text, estado from public.usuarios_perfiles where usuario_id = $1::uuid",
      [usuarioId],
    );
    return { usuarioId, perfil: r.rows[0] ?? null };
  }

  async function atender(req: IncomingMessage, res: ServerResponse) {
    const url = new URL(req.url ?? "/", "http://localhost");
    const ruta = url.pathname.replace(/\/+$/, "") || "/";
    const metodo = req.method ?? "GET";

    if (ruta === "/health" && metodo === "GET") {
      try {
        await pool.query("select 1");
        return enviar(res, 200, { status: "ok" });
      } catch {
        return enviar(res, 503, { status: "db_unavailable" });
      }
    }

    if (ruta.startsWith("/auth/v1/")) {
      if (config.anonKey && req.headers.apikey !== config.anonKey) {
        return enviar(res, 401, { message: "Invalid API key" });
      }
      if (ruta === "/auth/v1/token" && metodo === "POST") {
        const texto = await leerCuerpo(req);
        let body: Record<string, unknown> = {};
        try {
          body = texto ? JSON.parse(texto) : {};
        } catch {
          return enviar(res, 400, { code: "bad_json", msg: "Invalid JSON" });
        }
        const r = await auth.token(url.searchParams.get("grant_type"), body);
        return enviar(res, r.status, r.body);
      }
      if (ruta === "/auth/v1/user" && metodo === "GET") {
        const r = await auth.usuario(tokenBearer(req));
        return enviar(res, r.status, r.body);
      }
      if (ruta === "/auth/v1/logout" && metodo === "POST") {
        const r = await auth.logout(tokenBearer(req));
        return enviar(res, r.status, r.body);
      }
      return enviar(res, 404, { code: "not_found", msg: "Not found" });
    }

    if (ruta === "/api/sync/download" && metodo === "GET") {
      const s = await sesionDe(req);
      if ("status" in s) return enviar(res, s.status, s.body);
      const r = await descargarMaestros(s, new RepositorioPg(pool, s.usuarioId), { registro });
      return enviar(res, r.status, r.body);
    }

    if (ruta === "/api/sync/upload" && metodo === "POST") {
      const s = await sesionDe(req);
      if ("status" in s) return enviar(res, s.status, s.body);
      let body: unknown;
      try {
        body = JSON.parse(await leerCuerpo(req));
      } catch (e) {
        if (e instanceof CuerpoDemasiadoGrande) throw e;
        return enviar(res, 400, { success: false, message: "JSON inválido." });
      }
      const r = await subirLibro(s, new RepositorioPg(pool, s.usuarioId), body, { registro });
      return enviar(res, r.status, r.body);
    }

    return enviar(res, 404, { success: false, message: "Ruta no encontrada." });
  }

  return createServer((req, res) => {
    const inicio = Date.now();
    res.on("finish", () =>
      registro.info(`${req.method} ${req.url} ${res.statusCode} ${Date.now() - inicio}ms`),
    );
    atender(req, res).catch((e) => {
      if (e instanceof CuerpoDemasiadoGrande) {
        return enviar(res, 413, { success: false, message: "El cuerpo excede 10 MB." });
      }
      registro.error("Error no controlado", e);
      if (!res.headersSent) enviar(res, 500, { success: false, message: "Error interno." });
    });
  });
}

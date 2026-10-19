import { randomBytes, randomUUID } from "node:crypto";

import type { Pool } from "pg";

import { firmarJwt, verificarJwt } from "./jwt";

/**
 * Subconjunto de Supabase Auth (GoTrue) que usa la app móvil:
 *   POST /auth/v1/token?grant_type=password
 *   POST /auth/v1/token?grant_type=refresh_token
 *   GET  /auth/v1/user
 *   POST /auth/v1/logout
 * Las respuestas tienen la forma que espera supabase_flutter.
 */

export type RespuestaAuth = { status: number; body: unknown };

type FilaUsuario = {
  id: string;
  email: string;
  role: string;
  aud: string;
  raw_app_meta_data: Record<string, unknown>;
  raw_user_meta_data: Record<string, unknown>;
  email_confirmed_at: Date | null;
  last_sign_in_at: Date | null;
  created_at: Date;
  updated_at: Date;
};

const COLUMNAS = `id::text, email, role, aud, raw_app_meta_data, raw_user_meta_data,
  email_confirmed_at, last_sign_in_at, created_at, updated_at`;

const iso = (d: Date | null) => (d ? d.toISOString() : null);

function usuarioJson(u: FilaUsuario) {
  return {
    id: u.id,
    aud: u.aud,
    role: u.role,
    email: u.email,
    phone: "",
    email_confirmed_at: iso(u.email_confirmed_at),
    confirmed_at: iso(u.email_confirmed_at),
    last_sign_in_at: iso(u.last_sign_in_at),
    app_metadata: u.raw_app_meta_data,
    user_metadata: u.raw_user_meta_data,
    identities: [],
    created_at: iso(u.created_at),
    updated_at: iso(u.updated_at),
  };
}

function errorGoTrue(status: number, codigo: string, mensaje: string): RespuestaAuth {
  return {
    status,
    body: { code: codigo, error_code: codigo, msg: mensaje, error: codigo, error_description: mensaje },
  };
}

export class ServicioAuth {
  constructor(
    private readonly pool: Pool,
    private readonly secreto: string,
    private readonly expiraSegundos: number,
  ) {}

  private async emitirSesion(u: FilaUsuario): Promise<RespuestaAuth> {
    const ahora = Math.floor(Date.now() / 1000);
    const exp = ahora + this.expiraSegundos;
    const accessToken = firmarJwt(
      {
        sub: u.id,
        email: u.email,
        role: "authenticated",
        aud: "authenticated",
        iat: ahora,
        exp,
        session_id: randomUUID(),
      },
      this.secreto,
    );
    const refreshToken = randomBytes(24).toString("base64url");
    await this.pool.query("insert into auth.refresh_tokens (token, user_id) values ($1, $2)", [
      refreshToken,
      u.id,
    ]);
    return {
      status: 200,
      body: {
        access_token: accessToken,
        token_type: "bearer",
        expires_in: this.expiraSegundos,
        expires_at: exp,
        refresh_token: refreshToken,
        user: usuarioJson(u),
      },
    };
  }

  async token(grantType: string | null, body: Record<string, unknown>): Promise<RespuestaAuth> {
    if (grantType === "password") {
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      const password = typeof body.password === "string" ? body.password : "";
      if (!email || !password) {
        return errorGoTrue(400, "validation_failed", "Missing email or password");
      }
      const r = await this.pool.query<FilaUsuario>(
        `update auth.users set last_sign_in_at = now()
          where lower(email) = $1 and encrypted_password = crypt($2, encrypted_password)
          returning ${COLUMNAS}`,
        [email, password],
      );
      const u = r.rows[0];
      if (!u) return errorGoTrue(400, "invalid_credentials", "Invalid login credentials");
      return this.emitirSesion(u);
    }

    if (grantType === "refresh_token") {
      const refresh = typeof body.refresh_token === "string" ? body.refresh_token : "";
      // Rotación: el refresh token usado queda revocado.
      const r = await this.pool.query<FilaUsuario>(
        `with usado as (
           update auth.refresh_tokens set revoked = true
            where token = $1 and not revoked
            returning user_id
         )
         select ${COLUMNAS} from auth.users where id = (select user_id from usado)`,
        [refresh],
      );
      const u = r.rows[0];
      if (!u) {
        return errorGoTrue(
          400,
          "refresh_token_not_found",
          "Invalid Refresh Token: Refresh Token Not Found",
        );
      }
      return this.emitirSesion(u);
    }

    return errorGoTrue(400, "unsupported_grant_type", `Unsupported grant type: ${grantType}`);
  }

  /** Devuelve el id del usuario dueño del token, o null si no es válido. */
  async usuarioDelToken(token: string): Promise<string | null> {
    const claims = verificarJwt(token, this.secreto);
    if (!claims) return null;
    const r = await this.pool.query<{ id: string }>(
      "select id::text from auth.users where id = $1::uuid",
      [claims.sub],
    );
    return r.rows[0]?.id ?? null;
  }

  async usuario(token: string): Promise<RespuestaAuth> {
    const claims = verificarJwt(token, this.secreto);
    if (!claims) return errorGoTrue(401, "bad_jwt", "invalid JWT");
    const r = await this.pool.query<FilaUsuario>(
      `select ${COLUMNAS} from auth.users where id = $1::uuid`,
      [claims.sub],
    );
    const u = r.rows[0];
    if (!u) return errorGoTrue(404, "user_not_found", "User not found");
    return { status: 200, body: usuarioJson(u) };
  }

  async logout(token: string): Promise<RespuestaAuth> {
    const claims = verificarJwt(token, this.secreto);
    if (!claims) return errorGoTrue(401, "bad_jwt", "invalid JWT");
    await this.pool.query("update auth.refresh_tokens set revoked = true where user_id = $1::uuid", [
      claims.sub,
    ]);
    return { status: 204, body: null };
  }
}

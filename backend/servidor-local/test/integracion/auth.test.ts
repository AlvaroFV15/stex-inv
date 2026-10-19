import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import { CORREO, ID, iniciarEntorno, limpiar, login, pedir, type Entorno } from "./entorno";

let e: Entorno;
before(async () => {
  e = await iniciarEntorno();
  await limpiar(e.pool);
});
after(() => e.cerrar());

describe("Auth compatible con Supabase (/auth/v1)", () => {
  it("GET /health responde ok", async () => {
    const r = await pedir(e.url, "/health");
    assert.equal(r.status, 200);
    assert.equal(r.json.status, "ok");
  });

  it("login con contraseña devuelve una sesión con la forma de GoTrue", async () => {
    const r = await pedir(e.url, "/auth/v1/token?grant_type=password", {
      body: { email: CORREO.almacen1, password: "Stex2026!", gotrue_meta_security: {} },
    });
    assert.equal(r.status, 200);
    assert.equal(r.json.token_type, "bearer");
    assert.equal(typeof r.json.access_token, "string");
    assert.equal(typeof r.json.refresh_token, "string");
    assert.ok(r.json.expires_in > 0);
    assert.equal(r.json.user.id, ID.usuarioAlmacen1);
    assert.equal(r.json.user.email, CORREO.almacen1);
    assert.equal(r.json.user.aud, "authenticated");
    assert.equal(typeof r.json.user.created_at, "string");
    assert.equal(typeof r.json.user.app_metadata, "object");

    const payload = JSON.parse(Buffer.from(r.json.access_token.split(".")[1], "base64url").toString());
    assert.equal(payload.sub, ID.usuarioAlmacen1);
    assert.equal(payload.exp, r.json.expires_at);
  });

  it("el correo no distingue mayúsculas", async () => {
    const s = await login(e.url, "ALMACEN1@ApjlTextil.com");
    assert.equal(s.user.id, ID.usuarioAlmacen1);
  });

  for (const [nombre, body] of [
    ["contraseña incorrecta", { email: CORREO.almacen1, password: "mala" }],
    ["correo inexistente", { email: "nadie@apjltextil.com", password: "Stex2026!" }],
  ] as const) {
    it(`400 invalid_credentials con ${nombre}`, async () => {
      const r = await pedir(e.url, "/auth/v1/token?grant_type=password", { body });
      assert.equal(r.status, 400);
      assert.equal(r.json.code, "invalid_credentials");
      assert.equal(r.json.msg, "Invalid login credentials");
    });
  }

  it("400 si faltan correo o contraseña", async () => {
    const r = await pedir(e.url, "/auth/v1/token?grant_type=password", { body: {} });
    assert.equal(r.status, 400);
  });

  it("400 con grant_type no soportado", async () => {
    const r = await pedir(e.url, "/auth/v1/token?grant_type=magic", { body: {} });
    assert.equal(r.status, 400);
    assert.equal(r.json.code, "unsupported_grant_type");
  });

  it("refresh_token rota el token: el usado deja de servir", async () => {
    const s = await login(e.url, CORREO.almacen1);
    const r1 = await pedir(e.url, "/auth/v1/token?grant_type=refresh_token", {
      body: { refresh_token: s.refresh_token },
    });
    assert.equal(r1.status, 200);
    assert.notEqual(r1.json.refresh_token, s.refresh_token);

    const r2 = await pedir(e.url, "/auth/v1/token?grant_type=refresh_token", {
      body: { refresh_token: s.refresh_token },
    });
    assert.equal(r2.status, 400);
    assert.equal(r2.json.code, "refresh_token_not_found");
  });

  it("GET /auth/v1/user con token válido e inválido", async () => {
    const s = await login(e.url, CORREO.almacen1);
    const ok = await pedir(e.url, "/auth/v1/user", { token: s.access_token });
    assert.equal(ok.status, 200);
    assert.equal(ok.json.email, CORREO.almacen1);

    const mal = await pedir(e.url, "/auth/v1/user", { token: "x.y.z" });
    assert.equal(mal.status, 401);
  });

  it("logout responde 204 y revoca los refresh tokens", async () => {
    const s = await login(e.url, CORREO.almacen1);
    const r = await pedir(e.url, "/auth/v1/logout?scope=global", { metodo: "POST", token: s.access_token });
    assert.equal(r.status, 204);
    const refresh = await pedir(e.url, "/auth/v1/token?grant_type=refresh_token", {
      body: { refresh_token: s.refresh_token },
    });
    assert.equal(refresh.status, 400);
  });

  it("404 en rutas desconocidas", async () => {
    assert.equal((await pedir(e.url, "/auth/v1/otp", { body: {} })).status, 404);
    assert.equal((await pedir(e.url, "/api/otra")).status, 404);
  });
});

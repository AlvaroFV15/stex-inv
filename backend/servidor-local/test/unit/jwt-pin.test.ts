import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { hashPin } from "../../../parche-panel/lib/sync/pin";
import { firmarJwt, verificarJwt } from "../../src/jwt";

const SECRETO = "secreto-de-pruebas-con-mas-de-32-caracteres";

describe("hashPin", () => {
  it("coincide con el vector usado en la app móvil (pin_hash.dart)", () => {
    assert.equal(
      hashPin("8d9e0f1a-2b3c-4d5e-6f7a-8b9c0d1e2f3a", "1234"),
      "5d073a17585244f3a25ca8c8e7bd695507a736ebce0ff416f8a6d284f17a8e29",
    );
  });

  it("el mismo PIN da hashes distintos para operarios distintos", () => {
    assert.notEqual(hashPin("a", "1234"), hashPin("b", "1234"));
  });
});

describe("JWT HS256", () => {
  const claims = { sub: "u1", role: "authenticated", aud: "authenticated", iat: 1000, exp: 2000 };

  it("firma y verifica", () => {
    const t = firmarJwt(claims, SECRETO);
    assert.deepEqual(verificarJwt(t, SECRETO, 1500), claims);
  });

  it("rechaza token expirado", () => {
    assert.equal(verificarJwt(firmarJwt(claims, SECRETO), SECRETO, 2000), null);
  });

  it("rechaza firma con otro secreto", () => {
    assert.equal(verificarJwt(firmarJwt(claims, "otro-secreto-distinto-de-mas-de-32-chars"), SECRETO, 1500), null);
  });

  it("rechaza token alterado", () => {
    const [h, , f] = firmarJwt(claims, SECRETO).split(".");
    const cuerpo = Buffer.from(JSON.stringify({ ...claims, sub: "admin" })).toString("base64url");
    assert.equal(verificarJwt(`${h}.${cuerpo}.${f}`, SECRETO, 1500), null);
  });

  it("rechaza alg distinto de HS256 y basura", () => {
    const h = Buffer.from(JSON.stringify({ alg: "none" })).toString("base64url");
    const c = Buffer.from(JSON.stringify(claims)).toString("base64url");
    assert.equal(verificarJwt(`${h}.${c}.`, SECRETO, 1500), null);
    assert.equal(verificarJwt("no-es-un-jwt", SECRETO), null);
    assert.equal(verificarJwt("a.b.c", SECRETO), null);
  });
});

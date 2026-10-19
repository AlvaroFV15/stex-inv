import { createHmac, timingSafeEqual } from "node:crypto";

/** JWT HS256 mínimo, con los mismos claims que emite Supabase Auth. */

export type Claims = {
  sub: string;
  email?: string;
  role: string;
  aud: string;
  iat: number;
  exp: number;
  session_id?: string;
};

const b64 = (v: string | Buffer) => Buffer.from(v).toString("base64url");

export function firmarJwt(claims: Claims, secreto: string): string {
  const cabecera = b64(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const cuerpo = b64(JSON.stringify(claims));
  const firma = createHmac("sha256", secreto).update(`${cabecera}.${cuerpo}`).digest("base64url");
  return `${cabecera}.${cuerpo}.${firma}`;
}

/** Devuelve los claims si la firma es válida y no expiró; si no, null. */
export function verificarJwt(
  token: string,
  secreto: string,
  ahoraSegundos: number = Math.floor(Date.now() / 1000),
): Claims | null {
  const partes = token.split(".");
  if (partes.length !== 3) return null;
  const [cabecera, cuerpo, firma] = partes as [string, string, string];

  try {
    const h = JSON.parse(Buffer.from(cabecera, "base64url").toString("utf8"));
    if (h.alg !== "HS256") return null;

    const esperada = createHmac("sha256", secreto).update(`${cabecera}.${cuerpo}`).digest();
    const recibida = Buffer.from(firma, "base64url");
    if (recibida.length !== esperada.length || !timingSafeEqual(recibida, esperada)) {
      return null;
    }

    const claims = JSON.parse(Buffer.from(cuerpo, "base64url").toString("utf8")) as Claims;
    if (typeof claims.sub !== "string" || typeof claims.exp !== "number") return null;
    if (claims.exp <= ahoraSegundos) return null;
    return claims;
  } catch {
    return null;
  }
}

import { subirLibro } from "@/lib/sync/servicio";
import { autenticarPeticion, json } from "@/lib/sync/supabase";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** POST /api/sync/upload — recibe un libro de conteo cerrado en la tablet. */
export async function POST(request: Request) {
  const ctx = await autenticarPeticion(request);
  if (ctx instanceof Response) return ctx;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ success: false, message: "JSON inválido." }, 400);
  }

  const r = await subirLibro(ctx.sesion, ctx.repo, body, { registro: console });
  return json(r.body, r.status);
}

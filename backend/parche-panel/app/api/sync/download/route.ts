import { descargarMaestros } from "@/lib/sync/servicio";
import { autenticarPeticion, json } from "@/lib/sync/supabase";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** GET /api/sync/download — datos maestros para el modo offline de la tablet. */
export async function GET(request: Request) {
  const ctx = await autenticarPeticion(request);
  if (ctx instanceof Response) return ctx;

  const r = await descargarMaestros(ctx.sesion, ctx.repo, { registro: console });
  return json(r.body, r.status);
}

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import {
  ErrorRepositorio,
  type AlmacenFila,
  type CampanaFila,
  type LibroPayload,
  type MaterialFila,
  type OperarioFila,
  type Perfil,
  type RepositorioSync,
  type ResultadoRegistro,
  type Sesion,
} from "./contrato";

/**
 * Adaptador de Supabase para el panel Next.js.
 *
 * El cliente de `utils/supabase/server.ts` lee la sesión desde cookies, pero
 * la tablet manda `Authorization: Bearer <JWT>`. Aquí se crea un cliente por
 * petición con ese token, así las consultas respetan RLS como el usuario del
 * almacén.
 */

export function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

export type Contexto = { sesion: Sesion; repo: RepositorioSync };

export async function autenticarPeticion(request: Request): Promise<Contexto | Response> {
  const header = request.headers.get("authorization") ?? "";
  const token = /^bearer /i.test(header) ? header.slice(7).trim() : "";
  if (!token) {
    return json({ success: false, message: "Falta el token de autorización." }, 401);
  }

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) {
    return json({ success: false, message: "Sesión no válida o expirada." }, 401);
  }

  const { data: perfil } = await supabase
    .from("usuarios_perfiles")
    .select("rol, almacen_id, estado")
    .eq("usuario_id", data.user.id)
    .maybeSingle<Perfil>();

  return {
    sesion: { usuarioId: data.user.id, perfil: perfil ?? null },
    repo: new RepositorioSupabase(supabase),
  };
}

type ErrorPostgrest = { message: string; code?: string } | null;

function revisar<T>(r: { data: T | null; error: ErrorPostgrest }): T {
  if (r.error) throw new ErrorRepositorio(r.error.message, r.error.code);
  return (r.data ?? []) as T;
}

export class RepositorioSupabase implements RepositorioSync {
  constructor(private readonly supabase: SupabaseClient) {}

  async campanasAbiertas(): Promise<CampanaFila[]> {
    return revisar(
      await this.supabase
        .from("campanas_inventario")
        .select("campanas_id, nombre, fecha_inicio, fecha_fin")
        .eq("estado", "Abierta"),
    );
  }

  async almacenesActivos(almacenId: string | null): Promise<AlmacenFila[]> {
    let q = this.supabase
      .from("almacenes")
      .select("almacen_id, codigo_almacen, nro_almacen, razon_social, nombre_local")
      .eq("estado", true);
    if (almacenId) q = q.eq("almacen_id", almacenId);
    return revisar(await q);
  }

  async materialesActivos(): Promise<MaterialFila[]> {
    return revisar(
      await this.supabase
        .from("materiales")
        .select("material_id, codigo_material, kardex_numero, descripcion")
        .eq("estado", true),
    );
  }

  async operariosActivos(almacenId: string | null): Promise<OperarioFila[]> {
    let q = this.supabase
      .from("personal_planta")
      .select("operario_id, nombre_completo, pin_seguridad, almacen_id")
      .eq("estado", true);
    if (almacenId) q = q.eq("almacen_id", almacenId);
    return revisar(await q);
  }

  async registrarLibro(payload: LibroPayload): Promise<ResultadoRegistro> {
    const { data, error } = await this.supabase.rpc("registrar_libro_conteo", {
      p_payload: payload,
    });
    if (error) throw new ErrorRepositorio(error.message, error.code);
    const r = (data ?? {}) as Partial<ResultadoRegistro>;
    return { libro_id: r.libro_id ?? payload.libro_id, duplicado: Boolean(r.duplicado) };
  }
}

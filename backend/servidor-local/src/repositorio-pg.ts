import type { Pool } from "pg";

import {
  ErrorRepositorio,
  type AlmacenFila,
  type CampanaFila,
  type LibroPayload,
  type MaterialFila,
  type OperarioFila,
  type RepositorioSync,
  type ResultadoRegistro,
} from "../../parche-panel/lib/sync/contrato";

type ErrorPg = Error & { code?: string };

function envolver(e: unknown): ErrorRepositorio {
  const err = e as ErrorPg;
  return new ErrorRepositorio(err?.message ?? String(e), err?.code);
}

/**
 * Implementación con `pg` del repositorio de sincronización.
 * Hace las mismas consultas que RepositorioSupabase del panel.
 */
export class RepositorioPg implements RepositorioSync {
  constructor(
    private readonly pool: Pool,
    private readonly usuarioId: string,
  ) {}

  private async consultar<T>(sql: string, params: unknown[] = []): Promise<T[]> {
    try {
      return (await this.pool.query(sql, params)).rows as T[];
    } catch (e) {
      throw envolver(e);
    }
  }

  campanasAbiertas(): Promise<CampanaFila[]> {
    return this.consultar<CampanaFila>(
      `select campanas_id::text, nombre,
              to_char(fecha_inicio, 'YYYY-MM-DD') as fecha_inicio,
              to_char(fecha_fin, 'YYYY-MM-DD') as fecha_fin
         from public.campanas_inventario
        where estado = 'Abierta'
        order by fecha_inicio desc nulls last`,
    );
  }

  almacenesActivos(almacenId: string | null): Promise<AlmacenFila[]> {
    return this.consultar<AlmacenFila>(
      `select almacen_id::text, codigo_almacen, nro_almacen, razon_social, nombre_local
         from public.almacenes
        where estado and ($1::uuid is null or almacen_id = $1::uuid)
        order by razon_social`,
      [almacenId],
    );
  }

  materialesActivos(): Promise<MaterialFila[]> {
    return this.consultar<MaterialFila>(
      `select material_id::text, codigo_material, kardex_numero, descripcion
         from public.materiales
        where estado
        order by descripcion`,
    );
  }

  operariosActivos(almacenId: string | null): Promise<OperarioFila[]> {
    return this.consultar<OperarioFila>(
      `select operario_id::text, nombre_completo, pin_seguridad, almacen_id::text
         from public.personal_planta
        where estado and ($1::uuid is null or almacen_id = $1::uuid)
        order by nombre_completo`,
      [almacenId],
    );
  }

  /**
   * Llama a la función SQL de la migración como lo haría PostgREST:
   * rol `authenticated` y claims del JWT en la sesión, dentro de una
   * transacción. Así también se prueba el GRANT de la migración.
   */
  async registrarLibro(payload: LibroPayload): Promise<ResultadoRegistro> {
    const cliente = await this.pool.connect();
    try {
      await cliente.query("begin");
      await cliente.query(
        `select set_config('request.jwt.claims', $1, true),
                set_config('request.jwt.claim.sub', $2, true)`,
        [JSON.stringify({ sub: this.usuarioId, role: "authenticated" }), this.usuarioId],
      );
      await cliente.query("set local role authenticated");
      const r = await cliente.query<{ r: ResultadoRegistro }>(
        "select public.registrar_libro_conteo($1::jsonb) as r",
        [JSON.stringify(payload)],
      );
      await cliente.query("commit");
      return r.rows[0]!.r;
    } catch (e) {
      await cliente.query("rollback").catch(() => {});
      throw envolver(e);
    } finally {
      cliente.release();
    }
  }
}

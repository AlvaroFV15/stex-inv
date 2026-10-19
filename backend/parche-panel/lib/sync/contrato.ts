/**
 * Contrato de la sincronización con las tablets (v2.1).
 *
 * Este módulo y los demás de `lib/sync` (excepto `supabase.ts`) no dependen
 * de Next.js ni de Supabase: los usa el panel en producción y también el
 * servidor local de pruebas en Docker, así ambos aplican exactamente las
 * mismas reglas.
 */

export type Perfil = {
  rol: string | null;
  almacen_id: string | null;
  estado: boolean | null;
};

/** Quién hace la petición, ya autenticado. */
export type Sesion = {
  usuarioId: string;
  perfil: Perfil | null;
};

/** Resultado listo para enviar como JSON. */
export type Respuesta = {
  status: number;
  body: Record<string, unknown>;
};

export type CampanaFila = {
  campanas_id: string;
  nombre: string;
  fecha_inicio: string | null;
  fecha_fin: string | null;
};

export type AlmacenFila = {
  almacen_id: string;
  codigo_almacen: string | null;
  nro_almacen: string | null;
  razon_social: string | null;
  nombre_local: string | null;
};

export type MaterialFila = {
  material_id: string;
  codigo_material: string | null;
  kardex_numero: string | null;
  descripcion: string;
};

export type OperarioFila = {
  operario_id: string;
  nombre_completo: string;
  pin_seguridad: string | null;
  almacen_id: string | null;
};

export type DetalleLibro = {
  material_id: string;
  cantidad_unidad: number;
  peso_neto: number;
  observacion: string | null;
  fecha_registro: string | null;
};

export type LibroPayload = {
  libro_id: string;
  campana_id: string;
  almacen_id: string;
  operario_id: string | null;
  fecha_conteo: string | null;
  fecha_cierre: string | null;
  detalles: DetalleLibro[];
};

export type ResultadoRegistro = {
  libro_id: string;
  duplicado: boolean;
};

/** Error de la capa de datos. `codigo` es el SQLSTATE de PostgreSQL si existe. */
export class ErrorRepositorio extends Error {
  readonly codigo: string | undefined;

  constructor(mensaje: string, codigo?: string) {
    super(mensaje);
    this.name = "ErrorRepositorio";
    this.codigo = codigo;
  }
}

/** Acceso a datos. Lo implementan Supabase (panel) y `pg` (servidor local). */
export interface RepositorioSync {
  campanasAbiertas(): Promise<CampanaFila[]>;
  /** `null` = todos los almacenes activos (cuenta Admin). */
  almacenesActivos(almacenId: string | null): Promise<AlmacenFila[]>;
  materialesActivos(): Promise<MaterialFila[]>;
  /** `null` = operarios activos de todos los almacenes (cuenta Admin). */
  operariosActivos(almacenId: string | null): Promise<OperarioFila[]>;
  /** Guarda libro + detalles en una transacción. Idempotente por libro_id. */
  registrarLibro(payload: LibroPayload): Promise<ResultadoRegistro>;
}

export interface Registro {
  error(mensaje: string, detalle?: unknown): void;
}

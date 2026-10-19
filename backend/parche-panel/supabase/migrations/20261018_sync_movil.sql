-- =====================================================================
-- STEX-INV · Cambios de base de datos para la app móvil (sync v2.1)
-- Ejecutar en Supabase → SQL Editor. Es idempotente: se puede correr
-- más de una vez sin romper nada.
-- =====================================================================

-- 1) Trazabilidad: quién contó, cuándo se contó y desde dónde llegó.
alter table public.libros_conteo
  add column if not exists operario_id  uuid references public.personal_planta(operario_id),
  add column if not exists fecha_conteo timestamptz,
  add column if not exists fecha_cierre timestamptz,
  add column if not exists origen       text not null default 'web';

alter table public.movimientos_inventario
  add column if not exists operario_id    uuid references public.personal_planta(operario_id),
  add column if not exists fecha_registro timestamptz;

-- 2) Registro transaccional e idempotente de un libro enviado por la tablet.
--
--    · Transaccional: el libro y todos sus detalles se guardan juntos o no
--      se guarda nada (reemplaza el "rollback manual" del route handler).
--    · Idempotente: el libro_id lo genera el dispositivo. Si la tablet
--      reenvía un libro que ya llegó (porque se cortó la red antes de
--      recibir la respuesta), no se duplica: se devuelve duplicado = true.
--
--    security invoker: corre con los permisos (y las políticas RLS) del
--    usuario autenticado, igual que el insert que hacía antes la API.
create or replace function public.registrar_libro_conteo(p_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_libro     uuid := (p_payload->>'libro_id')::uuid;
  v_operario  uuid := nullif(p_payload->>'operario_id', '')::uuid;
  v_insertado integer;
begin
  if auth.uid() is null then
    raise exception 'No autenticado' using errcode = '28000';
  end if;

  if jsonb_typeof(p_payload->'detalles') <> 'array'
     or jsonb_array_length(p_payload->'detalles') = 0 then
    raise exception 'El libro no tiene detalles' using errcode = '22023';
  end if;

  insert into libros_conteo (
    libro_id, campana_id, almacen_id, usuario_id, operario_id,
    estado_general, fecha_conteo, fecha_cierre, origen
  )
  values (
    v_libro,
    (p_payload->>'campana_id')::uuid,
    (p_payload->>'almacen_id')::uuid,
    auth.uid(),
    v_operario,
    'Auditado',
    coalesce((p_payload->>'fecha_conteo')::timestamptz, now()),
    (p_payload->>'fecha_cierre')::timestamptz,
    'movil'
  )
  on conflict (libro_id) do nothing;

  get diagnostics v_insertado = row_count;
  if v_insertado = 0 then
    return jsonb_build_object('libro_id', v_libro, 'duplicado', true);
  end if;

  insert into movimientos_inventario (
    libro_id, material_id, cantidad_unidad, peso_neto, observacion,
    estado_sync, fecha_registro, operario_id
  )
  select
    v_libro,
    d.material_id,
    d.cantidad_unidad,
    d.peso_neto,
    nullif(btrim(d.observacion), ''),
    'Sincronizado',
    coalesce(d.fecha_registro, now()),
    v_operario
  from jsonb_to_recordset(p_payload->'detalles') as d(
    material_id     uuid,
    cantidad_unidad integer,
    peso_neto       numeric,
    observacion     text,
    fecha_registro  timestamptz
  );

  return jsonb_build_object('libro_id', v_libro, 'duplicado', false);
end;
$$;

revoke all on function public.registrar_libro_conteo(jsonb) from public, anon;
grant execute on function public.registrar_libro_conteo(jsonb) to authenticated;

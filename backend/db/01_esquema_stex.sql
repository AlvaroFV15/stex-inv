-- =====================================================================
-- Esquema del panel STEX-INV, reconstruido a partir del mapa del proyecto
-- (columnas usadas por el código). Sirve para el entorno local de pruebas.
--
-- Si tienes acceso al Supabase real, reemplaza este archivo por el volcado
-- exacto:   supabase db dump --schema public -f backend/db/01_esquema_stex.sql
-- =====================================================================

create table if not exists public.almacenes (
  almacen_id     uuid primary key default gen_random_uuid(),
  codigo_almacen text not null,
  nro_almacen    text,
  ruc            text,
  razon_social   text not null,
  nombre_local   text,
  estado         boolean not null default true
);

create table if not exists public.campanas_inventario (
  campanas_id  uuid primary key default gen_random_uuid(),
  nombre       text not null,
  fecha_inicio date,
  fecha_fin    date,
  estado       text not null default 'Abierta'
);

create table if not exists public.materiales (
  material_id     uuid primary key default gen_random_uuid(),
  codigo_material text not null,
  kardex_numero   text,
  descripcion     text not null,
  tipo            text,
  estado          boolean not null default true
);

create table if not exists public.personal_planta (
  operario_id     uuid primary key default gen_random_uuid(),
  nombre_completo text not null,
  pin_seguridad   text not null check (pin_seguridad ~ '^[0-9]{4}$'),
  almacen_id      uuid references public.almacenes(almacen_id),
  estado          boolean not null default true
);

create table if not exists public.usuarios_perfiles (
  usuario_id      uuid primary key references auth.users(id) on delete cascade,
  nombre_completo text,
  correo          text,
  rol             text not null default 'Operario' check (rol in ('Admin', 'Operario')),
  almacen_id      uuid references public.almacenes(almacen_id),
  estado          boolean not null default true,
  updated_at      timestamptz not null default now()
);

create table if not exists public.libros_conteo (
  libro_id       uuid primary key default gen_random_uuid(),
  campana_id     uuid not null references public.campanas_inventario(campanas_id),
  almacen_id     uuid not null references public.almacenes(almacen_id),
  usuario_id     uuid references auth.users(id),
  estado_general text not null default 'Pendiente',
  fecha_creacion timestamptz not null default now()
);

create table if not exists public.movimientos_inventario (
  movimiento_id   uuid primary key default gen_random_uuid(),
  libro_id        uuid not null references public.libros_conteo(libro_id) on delete cascade,
  material_id     uuid not null references public.materiales(material_id),
  cantidad_unidad integer not null,
  peso_neto       numeric(12, 3) not null,
  observacion     text,
  estado_sync     text not null default 'Pendiente'
);

create index if not exists idx_movimientos_libro on public.movimientos_inventario(libro_id);

grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated, service_role;

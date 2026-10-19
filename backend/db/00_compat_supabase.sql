-- =====================================================================
-- Compatibilidad mínima con Supabase para el entorno local de pruebas.
--
-- En Supabase real todo esto ya existe (esquema auth, roles, auth.uid()).
-- Aquí se recrea lo justo para que la migración del parche y el servidor
-- local funcionen igual que en producción. NO ejecutar en Supabase.
-- =====================================================================

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text not null unique,
  encrypted_password text not null,
  role               text not null default 'authenticated',
  aud                text not null default 'authenticated',
  raw_app_meta_data  jsonb not null default '{"provider":"email","providers":["email"]}',
  raw_user_meta_data jsonb not null default '{}',
  email_confirmed_at timestamptz default now(),
  last_sign_in_at    timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table if not exists auth.refresh_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  revoked    boolean not null default false,
  created_at timestamptz not null default now()
);

-- Misma definición que usa Supabase: el id del usuario sale de los claims
-- del JWT que PostgREST (o el servidor local) deja en la sesión.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

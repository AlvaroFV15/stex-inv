-- =====================================================================
-- Datos de prueba. Los UUID son fijos porque las pruebas automáticas los
-- usan. Contraseña de todas las cuentas: Stex2026!
--
--   almacen1@apjltextil.com     Operario · Textiles del Norte (A1)
--   almacen2@apjltextil.com     Operario · Sede Principal Cañete (A2)
--   admin@apjltextil.com        Admin    · ve todos los almacenes
--   desactivado@apjltextil.com  cuenta con perfil desactivado
--   sinalmacen@apjltextil.com   Operario sin almacén asignado
--
-- PIN de operarios: Juan Carlos Pérez 1234 · María Torres 4321 (A1)
--                   Pedro Ramos 1111 (A2) · Luis Inactivo 2222 (inactivo)
-- =====================================================================

insert into public.almacenes (almacen_id, codigo_almacen, nro_almacen, ruc, razon_social, nombre_local, estado) values
  ('a1000000-0000-4000-8000-000000000001', 'TEJ04', '9', '20100000001', 'Textiles del Norte S.A.C.', 'Planta Tejeduría', true),
  ('a1000000-0000-4000-8000-000000000002', 'CAN01', '3', '20100000002', 'APJL TEXTIL S.A.C.', 'Sede Principal Cañete', true),
  ('a1000000-0000-4000-8000-000000000003', 'OLD01', '1', '20100000003', 'Almacén Antiguo S.A.C.', 'Cerrado', false)
on conflict do nothing;

insert into public.campanas_inventario (campanas_id, nombre, fecha_inicio, fecha_fin, estado) values
  ('c1000000-0000-4000-8000-000000000001', 'Inventario Octubre 2026', '2026-10-01', '2026-10-31', 'Abierta'),
  ('c1000000-0000-4000-8000-000000000002', 'Inventario Septiembre 2026', '2026-09-01', '2026-09-30', 'Cerrada')
on conflict do nothing;

insert into public.materiales (material_id, codigo_material, kardex_numero, descripcion, tipo, estado) values
  ('b1000000-0000-4000-8000-000000000001', 'MAT-001', '1001', 'Hilo Algodón 30/1 Peinado', 'Hilo', true),
  ('b1000000-0000-4000-8000-000000000002', 'MAT-014', '1014', 'Crudo jersey 24/1', 'Tela', true),
  ('b1000000-0000-4000-8000-000000000003', 'MAT-020', '1020', 'Hilo poliéster 150D', 'Hilo', true),
  ('b1000000-0000-4000-8000-000000000004', 'MAT-099', '1099', 'Material descontinuado', 'Hilo', false)
on conflict do nothing;

insert into public.personal_planta (operario_id, nombre_completo, pin_seguridad, almacen_id, estado) values
  ('d1000000-0000-4000-8000-000000000001', 'Juan Carlos Pérez', '1234', 'a1000000-0000-4000-8000-000000000001', true),
  ('d1000000-0000-4000-8000-000000000002', 'María Torres',      '4321', 'a1000000-0000-4000-8000-000000000001', true),
  ('d1000000-0000-4000-8000-000000000003', 'Pedro Ramos',       '1111', 'a1000000-0000-4000-8000-000000000002', true),
  ('d1000000-0000-4000-8000-000000000004', 'Luis Inactivo',     '2222', 'a1000000-0000-4000-8000-000000000001', false)
on conflict do nothing;

insert into auth.users (id, email, encrypted_password) values
  ('e1000000-0000-4000-8000-000000000001', 'almacen1@apjltextil.com',    crypt('Stex2026!', gen_salt('bf'))),
  ('e1000000-0000-4000-8000-000000000002', 'almacen2@apjltextil.com',    crypt('Stex2026!', gen_salt('bf'))),
  ('e1000000-0000-4000-8000-000000000003', 'admin@apjltextil.com',       crypt('Stex2026!', gen_salt('bf'))),
  ('e1000000-0000-4000-8000-000000000004', 'desactivado@apjltextil.com', crypt('Stex2026!', gen_salt('bf'))),
  ('e1000000-0000-4000-8000-000000000005', 'sinalmacen@apjltextil.com',  crypt('Stex2026!', gen_salt('bf')))
on conflict do nothing;

insert into public.usuarios_perfiles (usuario_id, nombre_completo, correo, rol, almacen_id, estado) values
  ('e1000000-0000-4000-8000-000000000001', 'Almacén Textiles del Norte', 'almacen1@apjltextil.com',    'Operario', 'a1000000-0000-4000-8000-000000000001', true),
  ('e1000000-0000-4000-8000-000000000002', 'Almacén Cañete',             'almacen2@apjltextil.com',    'Operario', 'a1000000-0000-4000-8000-000000000002', true),
  ('e1000000-0000-4000-8000-000000000003', 'Administrador',              'admin@apjltextil.com',       'Admin',    null,                                   true),
  ('e1000000-0000-4000-8000-000000000004', 'Cuenta desactivada',         'desactivado@apjltextil.com', 'Operario', 'a1000000-0000-4000-8000-000000000001', false),
  ('e1000000-0000-4000-8000-000000000005', 'Cuenta sin almacén',         'sinalmacen@apjltextil.com',  'Operario', null,                                   true)
on conflict do nothing;

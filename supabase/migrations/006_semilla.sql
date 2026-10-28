-- Módulo de restaurante · 006 datos de Big Burger (generado por scripts/migraciones-modulo.py desde clientes/big-burger/cliente.json).
-- Se puede volver a correr: actualiza nombre y precio sin duplicar. Los precios están en centavos.
-- ATENCIÓN: los costos de envío por sector son DE EJEMPLO hasta que el cliente los confirme.
insert into big_burger.productos (clave, nombre, categoria, precio_cent, lema, ingredientes, foto, cuenta_burger, controla_stock, activo, orden) values
  ('clasica', 'La clásica', 'clasicas', 250, null, 'Pan tradicional, carne 140 g, lechuga, tomate y salsa de la casa', null, true, true, true, 0),
  ('cheddar', 'La cheddar', 'clasicas', 300, null, 'Pan tradicional, carne 140 g, queso cheddar, lechuga, tomate y salsa de la casa', null, true, true, true, 1),
  ('bacon', 'La bacon', 'clasicas', 350, null, 'Pan tradicional, carne 140 g, tocino, lechuga, tomate y salsa de la casa', null, true, true, true, 2),
  ('bacon-cheese', 'Bacon Cheese', 'clasicas', 400, null, 'Pan tradicional, carne 140 g, queso cheddar, tocino, lechuga, tomate y salsa de la casa', null, true, true, true, 3),
  ('americana', 'Americana', 'premium', 450, null, 'Pan de papa artesanal, carne 140 g, queso cheddar, vegetales, cebolla caramelizada y salsa de la casa', null, true, true, true, 4),
  ('hawaiian-bbq', 'Hawaiian BBQ', 'premium', 500, null, 'Pan de papa artesanal, carne 140 g, queso cheddar, tocino, jamón, piña a la plancha, vegetales y salsa de la casa', null, true, true, true, 5),
  ('doble-americana', 'Doble americana', 'premium', 550, null, 'Pan de papa artesanal, doble carne 140 g, doble queso cheddar, tocino y salsa de la casa', null, true, true, true, 6),
  ('big-mapple', 'Big Mapple Burger', 'insignia', 600, 'Pan de papa artesanal', 'Pan de papa artesanal, carne 140 g, tocino, queso, queso labneh, miel maple y salsa de la casa', null, true, true, true, 7),
  ('tocino-lovers', 'Tocino Lovers', 'insignia', 700, 'Pan de papa artesanal', 'Pan de papa artesanal, carne 140 g, doble queso, 4 tiras de tocino, cebolla caramelizada y salsa de la casa', null, true, true, true, 8),
  ('portobello', 'Portobello', 'insignia', 750, 'Pan de papa artesanal', 'Pan de papa artesanal, carne 140 g, queso, tocino, queso labneh, champiñones portobello y salsa de la casa', null, true, true, true, 9),
  ('bebida-gaseosa', 'Gaseosa personal', 'bebidas', 100, null, null, null, false, false, true, 10),
  ('bebida-agua', 'Agua sin gas', 'bebidas', 75, null, null, null, false, false, true, 11),
  ('bebida-jugo', 'Jugo natural', 'bebidas', 150, null, null, null, false, false, true, 12)
on conflict (clave) do update set nombre = excluded.nombre, categoria = excluded.categoria, precio_cent = excluded.precio_cent, lema = excluded.lema,
  ingredientes = excluded.ingredientes, foto = excluded.foto, cuenta_burger = excluded.cuenta_burger, controla_stock = excluded.controla_stock, orden = excluded.orden;

-- Sin sectores de entrega todavía (solo para llevar). Se agregan después con sector_guardar(nombre, costo_cent, true, orden) o regenerando esta semilla.

-- Primer dueño: crea el usuario en Supabase › Authentication › Add user (o reutiliza el que ya tenga por otro negocio) y luego corre, con su correo.
-- En el proyecto COMPARTIDO el registro público queda encendido a propósito (CLAUDE.md §4.10): no se apaga; el acceso lo da solo la tabla staff de este schema.
--   insert into big_burger.staff (user_id, nombre, rol) select id, 'Dueño', 'admin' from auth.users where lower(email) = lower('CORREO_DEL_DUEÑO');
-- Después el dueño da de alta a sus empleados desde la función equipo_guardar(correo, nombre, 'vendedor').

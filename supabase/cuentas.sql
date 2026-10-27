-- Big Burger · dar acceso a las cuentas (correr DESPUÉS de instalar-todo.sql y de crear los usuarios en Authentication › Users › Add user).
-- Cambia los correos por los reales. Cada línea busca el usuario por su correo y le da su rol en big_burger (si el correo no existe, no inserta nada).
--   admin    = dueño (dashboard, stock del día, anular, equipo)
--   vendedor = caja (confirmar pedidos, vender en mostrador)
--   pantalla = la tablet del local (solo crea pedidos)

insert into big_burger.staff (user_id, nombre, rol) select id, 'Dueño',    'admin'    from auth.users where lower(email) = lower('CORREO_DEL_DUEÑO');
insert into big_burger.staff (user_id, nombre, rol) select id, 'Caja',     'vendedor' from auth.users where lower(email) = lower('CORREO_DE_LA_CAJA');
insert into big_burger.staff (user_id, nombre, rol) select id, 'Pantalla', 'pantalla' from auth.users where lower(email) = lower('CORREO_DE_LA_TABLET');

-- Comprobar: deben salir las 3 filas con su rol.
select s.nombre, s.rol, u.email from big_burger.staff s join auth.users u on u.id = s.user_id order by s.rol;

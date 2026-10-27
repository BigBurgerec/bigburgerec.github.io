-- Módulo de restaurante · 008 pantalla en tienda (kiosco) y vencimiento de pedidos. Origen: Big Burger (Premium, oct 2026), siguiendo la estructura de MockaBox:
--   menú online (pedido_crear, 002) y pantalla en tienda (pedido_local, aquí) dejan el pedido PENDIENTE; la caja (personal.html) lo acepta o lo rechaza.
-- La tablet del local entra con su PROPIO usuario de Authentication con rol 'pantalla': solo puede crear pedidos del local, no ve ventas, stock ni caja.
--   Así no hay una función pública que cualquiera pueda llamar desde internet para meter pedidos falsos en la caja (§4.4); el acceso por clave lo protege Auth.
-- Un pedido de la pantalla no descuenta stock hasta que la caja lo acepta y se paga en caja (sin tarjeta prepago, sin pasarela: CLAUDE.md §3).
-- Los pendientes vencen solos a las config.pendiente_horas (3 por defecto): vencidos solo se pueden rechazar.
-- Esta migración REEMPLAZA de forma explícita (create or replace) a: es_staff (002), _venta_estado (001), pedidos_pendientes y pedido_resolver (003),
-- ventas_hoy (003) y equipo_guardar (004); _crear_venta (002) pasa a llamar a la nueva versión con «modo». Las versiones anteriores dejan de usarse.

-- ---------- esquema ----------
alter table big_burger.config
  add column pendiente_horas int not null default 3 check (pendiente_horas between 1 and 24),          -- un pedido pendiente vence a las N horas
  add column max_pedidos_pantalla int not null default 30 check (max_pedidos_pantalla between 1 and 300); -- pedidos de la pantalla cada 10 minutos (anti-spam)

alter table big_burger.staff drop constraint staff_rol_check;
alter table big_burger.staff add constraint staff_rol_check check (rol in ('admin', 'vendedor', 'pantalla'));

-- modo: en la pantalla el cliente elige comer aquí o para llevar (el canal sigue siendo 'local': es una venta del local).
alter table big_burger.ventas add column modo text check (modo is null or modo in ('aqui', 'llevar'));
alter table big_burger.ventas drop constraint ventas_origen_check;
alter table big_burger.ventas add constraint ventas_origen_check check (origen in ('staff', 'web', 'pantalla'));
alter table big_burger.ventas drop constraint ventas_check;
alter table big_burger.ventas add constraint ventas_check check (
  (origen = 'staff' and canal = 'local' and modo is null)
  or (origen = 'web' and canal in ('llevar', 'domicilio') and modo is null)
  or (origen = 'pantalla' and canal = 'local' and modo is not null));
create index ventas_pantalla_idx on big_burger.ventas (creado) where origen = 'pantalla';

-- ---------- reemplazos ----------
-- Motor de ventas con «modo» (comer aquí / para llevar de la pantalla). Mismo cuerpo que el de 002 más esa columna.
create function big_burger._crear_venta(
  p_canal text, p_origen text, p_estado text, p_staff uuid, p_clave text, p_cliente text, p_telefono text, p_sector text,
  p_direccion text, p_maps text, p_nota text, p_programado timestamptz, p_envio int, p_lineas jsonb, p_modo text
) returns bigint language plpgsql security definer set search_path = '' as $$
declare
  d date := big_burger.hoy_ec(); maxl int := (select max_unidades_linea from big_burger.config where id = 1);
  it record; prod big_burger.productos; id_v bigint; tot int := 0; uni int := 0; burg int := 0; num int; lineas jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('big_burger.ventas'));      -- serializa numeración y stock
  begin
    if jsonb_typeof(p_lineas) <> 'array' or jsonb_array_length(p_lineas) not between 1 and 20 then raise exception 'x'; end if;
    if exists (select 1 from jsonb_to_recordset(p_lineas) as x (producto text, cantidad int) where producto is null or cantidad is null) then raise exception 'x'; end if;
    -- mismas burgers repetidas se suman; el tope por producto se mide sobre el total
    select jsonb_agg(jsonb_build_object('producto', producto, 'cantidad', cant)) into lineas
    from (select producto, sum(cantidad)::int as cant from jsonb_to_recordset(p_lineas) as x (producto text, cantidad int) group by producto) g;
  exception when others then
    raise exception 'El pedido no es válido.';
  end;
  if exists (select 1 from jsonb_to_recordset(lineas) as x (producto text, cantidad int) where cantidad < 1 or cantidad > maxl) then
    raise exception 'Cada producto lleva entre 1 y % unidades.', maxl;
  end if;
  for it in select * from jsonb_to_recordset(lineas) as x (producto text, cantidad int) loop
    select * into prod from big_burger.productos where clave = it.producto and activo;
    if not found then raise exception 'Uno de los productos ya no está disponible.'; end if;
    perform big_burger._hay_stock(it.producto, it.cantidad, d);
    tot := tot + prod.precio_cent * it.cantidad; uni := uni + it.cantidad;
    if prod.cuenta_burger then burg := burg + it.cantidad; end if;
  end loop;
  select coalesce(max(numero), 0) + 1 into num from big_burger.ventas where dia = d;
  insert into big_burger.ventas (dia, numero, canal, origen, modo, estado, clave, staff_id, cliente, telefono, sector, direccion, maps_url, nota, programado,
                                 envio_cent, total_cent, unidades, hamburguesas, resuelto_en)
  values (d, num, p_canal, p_origen, p_modo, p_estado, p_clave, p_staff, p_cliente, p_telefono, p_sector, p_direccion, p_maps, p_nota, p_programado,
          p_envio, tot + p_envio, uni, burg, case when p_estado = 'confirmada' then now() end)
  returning id into id_v;
  insert into big_burger.venta_lineas (venta_id, producto, nombre, cantidad, precio_cent, cuenta_burger)
    select id_v, t.producto, p.nombre, t.cantidad, p.precio_cent, p.cuenta_burger
    from jsonb_to_recordset(lineas) as t (producto text, cantidad int) join big_burger.productos p on p.clave = t.producto;
  if p_estado = 'confirmada' then perform big_burger._descontar_stock(id_v, p_staff); end if;
  return id_v;
end $$;

-- La versión de 002 (sin modo) queda como atajo de la nueva, para web y mostrador.
create or replace function big_burger._crear_venta(
  p_canal text, p_origen text, p_estado text, p_staff uuid, p_clave text, p_cliente text, p_telefono text, p_sector text,
  p_direccion text, p_maps text, p_nota text, p_programado timestamptz, p_envio int, p_lineas jsonb
) returns bigint language sql security definer set search_path = '' as $$
  select big_burger._crear_venta(p_canal, p_origen, p_estado, p_staff, p_clave, p_cliente, p_telefono, p_sector, p_direccion, p_maps, p_nota, p_programado, p_envio, p_lineas, null::text) $$;

-- es_staff: la cuenta de la pantalla NO es personal (no vende, no ve caja ni stock).
create or replace function big_burger.es_staff() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from big_burger.staff where user_id = auth.uid() and activo and rol in ('admin', 'vendedor')) $$;
create function big_burger.es_pantalla() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from big_burger.staff where user_id = auth.uid() and activo and rol = 'pantalla') $$;

-- Inmutabilidad: igual que en 001, ahora también protege «modo».
create or replace function big_burger._venta_estado() returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'Las ventas no se borran: se anulan.'; end if;
  if old.estado = 'pendiente' and new.estado in ('confirmada', 'rechazada')
     and (old.id, old.dia, old.numero, old.canal, old.origen, old.modo, old.clave, old.cliente, old.telefono, old.sector, old.direccion, old.maps_url, old.nota,
          old.programado, old.envio_cent, old.total_cent, old.unidades, old.hamburguesas, old.creado, old.anulado_por, old.anulado_en, old.anulado_motivo)
         is not distinct from
         (new.id, new.dia, new.numero, new.canal, new.origen, new.modo, new.clave, new.cliente, new.telefono, new.sector, new.direccion, new.maps_url, new.nota,
          new.programado, new.envio_cent, new.total_cent, new.unidades, new.hamburguesas, new.creado, new.anulado_por, new.anulado_en, new.anulado_motivo) then
    return new;
  end if;
  if old.estado = 'confirmada' and new.estado = 'anulada'
     and (old.id, old.dia, old.numero, old.canal, old.origen, old.modo, old.clave, old.staff_id, old.cliente, old.telefono, old.sector, old.direccion, old.maps_url, old.nota,
          old.programado, old.envio_cent, old.total_cent, old.unidades, old.hamburguesas, old.creado, old.resuelto_en)
         is not distinct from
         (new.id, new.dia, new.numero, new.canal, new.origen, new.modo, new.clave, new.staff_id, new.cliente, new.telefono, new.sector, new.direccion, new.maps_url, new.nota,
          new.programado, new.envio_cent, new.total_cent, new.unidades, new.hamburguesas, new.creado, new.resuelto_en) then
    return new;
  end if;
  raise exception 'Una venta solo cambia de estado (pendiente → confirmada o rechazada; confirmada → anulada).';
end $$;

-- ¿Venció? Un pendiente vence a las N horas de creado (o de su hora programada) y siempre al cambiar de día.
create function big_burger._vencido(v big_burger.ventas) returns boolean language sql stable security definer set search_path = '' as $$
  select v.dia <> big_burger.hoy_ec()
      or greatest(v.creado, coalesce(v.programado, v.creado)) < now() - make_interval(hours => (select pendiente_horas from big_burger.config where id = 1)) $$;

-- Pedidos que esperan respuesta de la caja: de la web y de la pantalla, con su origen, modo y nota.
create or replace function big_burger.pedidos_pendientes() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  return coalesce((select json_agg(x order by (x->>'id')::bigint) from (
    select json_build_object('id', v.id, 'numero', v.numero, 'canal', v.canal, 'origen', v.origen, 'modo', v.modo, 'cliente', v.cliente, 'telefono', v.telefono,
        'sector', v.sector, 'direccion', v.direccion, 'maps_url', v.maps_url, 'nota', v.nota, 'programado', v.programado, 'envio_cent', v.envio_cent,
        'total_cent', v.total_cent, 'unidades', v.unidades, 'creado', v.creado, 'vencido', big_burger._vencido(v),
        'lineas', (select json_agg(json_build_object('nombre', l.nombre, 'cantidad', l.cantidad) order by l.id) from big_burger.venta_lineas l where l.venta_id = v.id)) as x
    from big_burger.ventas v where v.estado = 'pendiente' order by v.id limit 60) t), '[]'::json);
end $$;

-- Aceptar (entra a cocina: cuenta como vendida y descuenta stock) o rechazar. Vale para pedidos de la web y de la pantalla.
create or replace function big_burger.pedido_resolver(p_id bigint, p_accion text) returns void language plpgsql security definer set search_path = '' as $$
declare v big_burger.ventas; l record;
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  if p_accion not in ('confirmar', 'rechazar') then raise exception 'Acción no válida.'; end if;
  perform pg_advisory_xact_lock(hashtext('big_burger.ventas'));
  select * into v from big_burger.ventas where id = p_id for update;
  if not found or v.origen not in ('web', 'pantalla') then raise exception 'No existe ese pedido.'; end if;
  if v.estado <> 'pendiente' then raise exception 'Ese pedido ya fue resuelto.'; end if;
  if p_accion = 'rechazar' then
    update big_burger.ventas set estado = 'rechazada', staff_id = auth.uid(), resuelto_en = now() where id = p_id;
    return;
  end if;
  if big_burger._vencido(v) then raise exception 'Este pedido venció: solo se puede rechazar.'; end if;
  for l in select producto, cantidad from big_burger.venta_lineas where venta_id = p_id loop
    perform big_burger._hay_stock(l.producto, l.cantidad, v.dia);
  end loop;
  update big_burger.ventas set estado = 'confirmada', staff_id = auth.uid(), resuelto_en = now() where id = p_id;
  perform big_burger._descontar_stock(p_id, auth.uid());
end $$;

-- Ventas de hoy (igual que en 003) con origen y modo, para que la caja distinga web, pantalla y mostrador.
create or replace function big_burger.ventas_hoy() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  return coalesce((select json_agg(x order by (x->>'id')::bigint desc) from (
    select json_build_object('id', v.id, 'numero', v.numero, 'canal', v.canal, 'origen', v.origen, 'modo', v.modo, 'cliente', v.cliente, 'estado', v.estado,
        'total_cent', v.total_cent, 'unidades', v.unidades, 'creado', v.creado, 'quien', s.nombre, 'puede_anular', v.estado = 'confirmada' and (big_burger.es_admin()
           or (v.staff_id = auth.uid() and now() - coalesce(v.resuelto_en, v.creado) <= make_interval(mins => (select anular_minutos from big_burger.config where id = 1)))),
        'lineas', (select json_agg(json_build_object('nombre', l.nombre, 'cantidad', l.cantidad) order by l.id) from big_burger.venta_lineas l where l.venta_id = v.id)) as x
    from big_burger.ventas v left join big_burger.staff s on s.user_id = v.staff_id
    where v.dia = big_burger.hoy_ec() and v.estado in ('confirmada', 'anulada') and (big_burger.es_admin() or v.staff_id = auth.uid())
    order by v.id desc limit 100) t), '[]'::json);
end $$;

-- El dueño da de alta también la cuenta de la pantalla (rol 'pantalla').
create or replace function big_burger.equipo_guardar(p_correo text, p_nombre text, p_rol text, p_activo boolean default true) returns void language plpgsql security definer set search_path = '' as $$
declare u uuid;
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño.'; end if;
  if p_rol not in ('admin', 'vendedor', 'pantalla') then raise exception 'Rol no válido.'; end if;
  select id into u from auth.users where lower(email) = lower(trim(p_correo));
  if u is null then raise exception 'Ese correo no tiene usuario. Créalo primero en Supabase › Authentication › Add user.'; end if;
  if u = auth.uid() and (p_rol <> 'admin' or not coalesce(p_activo, true)) then raise exception 'No puedes quitarte tu propio acceso de dueño.'; end if;
  insert into big_burger.staff (user_id, nombre, rol, activo) values (u, coalesce(nullif(trim(p_nombre), ''), split_part(p_correo, '@', 1)), p_rol, coalesce(p_activo, true))
  on conflict (user_id) do update set nombre = excluded.nombre, rol = excluded.rol, activo = excluded.activo;
end $$;

-- ---------- pantalla en tienda ----------
-- ¿Quién soy? para la tablet (no usa yo(), que es del personal).
create function big_burger.pantalla_yo() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not (big_burger.es_pantalla() or big_burger.es_admin()) then raise exception 'Esta cuenta no es la pantalla del local.'; end if;
  return json_build_object('ok', true, 'dia', big_burger.hoy_ec());
end $$;

-- Pedido hecho en la tablet. Nace PENDIENTE, se paga en caja. Precios y total los calcula la base (§4.5).
-- p_modo: 'aqui' (comer aquí) o 'llevar'. El dueño también puede usarla (para probar la tablet con su cuenta).
create function big_burger.pedido_local(p_nombre text, p_modo text, p_nota text, p_lineas jsonb) returns json language plpgsql security definer set search_path = '' as $$
declare c big_burger.config; id_v bigint; v big_burger.ventas;
begin
  if not (big_burger.es_pantalla() or big_burger.es_admin()) then raise exception 'Esta cuenta no es la pantalla del local.'; end if;
  if length(trim(coalesce(p_nombre, ''))) < 2 or length(p_nombre) > 40 then raise exception 'Escribe tu nombre.'; end if;
  if p_modo not in ('aqui', 'llevar') then raise exception 'Elige comer aquí o para llevar.'; end if;
  if length(coalesce(p_nota, '')) > 200 then raise exception 'La nota es muy larga.'; end if;
  select * into c from big_burger.config where id = 1;
  if (select count(*) from big_burger.ventas where origen = 'pantalla' and creado > now() - interval '10 minutes') >= c.max_pedidos_pantalla then
    raise exception 'Hay muchos pedidos en cola. Acércate a la caja, por favor.';
  end if;
  id_v := big_burger._crear_venta('local', 'pantalla', 'pendiente', null, null, trim(p_nombre), null, null, null, null, nullif(trim(coalesce(p_nota, '')), ''), null, 0, p_lineas, p_modo);
  select * into v from big_burger.ventas where id = id_v;
  return json_build_object('numero', v.numero, 'total_cent', v.total_cent);
end $$;

-- ---------- permisos (§4.3) ----------
revoke all on function big_burger.es_pantalla(), big_burger._vencido(big_burger.ventas), big_burger.pantalla_yo(), big_burger.pedido_local(text, text, text, jsonb),
  big_burger._crear_venta(text, text, text, uuid, text, text, text, text, text, text, text, timestamptz, int, jsonb, text) from public, anon, authenticated;
grant execute on function big_burger.pantalla_yo(), big_burger.pedido_local(text, text, text, jsonb) to authenticated;   -- cada una comprueba el rol por dentro
-- create or replace conserva los permisos que ya tenían (es_staff, _venta_estado, pedidos_pendientes, pedido_resolver, ventas_hoy, equipo_guardar).

-- Módulo de restaurante · 002 ayudas internas, motor de ventas y funciones públicas (anon).
-- Todas: security definer + set search_path = '' (§4.2). Los permisos se fijan en 005.

-- ---------- ayudas internas (nadie las llama desde fuera) ----------
create function big_burger.tel(p text) returns text language sql immutable set search_path = '' as $$
  select case when d ~ '^09[0-9]{8}$' then '593' || substr(d, 2) when d ~ '^593[0-9]{9}$' then d else '' end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x $$;

create function big_burger.hoy_ec() returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Guayaquil')::date $$;

create function big_burger.rol() returns text language sql stable security definer set search_path = '' as $$
  select rol from big_burger.staff where user_id = auth.uid() and activo $$;
create function big_burger.es_staff() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from big_burger.staff where user_id = auth.uid() and activo) $$;
create function big_burger.es_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from big_burger.staff where user_id = auth.uid() and activo and rol = 'admin') $$;

-- Saldo de stock de un producto en un día. null = el dueño aún no cargó stock de ese producto hoy (se vende sin tope, el dashboard avisa).
create function big_burger.stock_saldo(p_prod text, p_dia date) returns int language sql stable security definer set search_path = '' as $$
  select case when exists (select 1 from big_burger.stock_mov where dia = p_dia and producto = p_prod and motivo in ('carga', 'ajuste'))
              then (select coalesce(sum(delta), 0)::int from big_burger.stock_mov where dia = p_dia and producto = p_prod) end $$;

-- Unidades vendidas (ventas confirmadas) de un producto en un día.
create function big_burger.vendidas(p_prod text, p_dia date) returns int language sql stable security definer set search_path = '' as $$
  select coalesce(sum(l.cantidad), 0)::int from big_burger.venta_lineas l join big_burger.ventas v on v.id = l.venta_id
  where l.producto = p_prod and v.dia = p_dia and v.estado = 'confirmada' $$;

-- Descuenta del stock las líneas de una venta (solo productos con stock cargado hoy y que lo controlan).
create function big_burger._descontar_stock(p_venta bigint, p_staff uuid) returns void language plpgsql security definer set search_path = '' as $$
declare v big_burger.ventas; r record;
begin
  select * into v from big_burger.ventas where id = p_venta;
  for r in select l.producto, l.cantidad from big_burger.venta_lineas l join big_burger.productos p on p.clave = l.producto
           where l.venta_id = p_venta and p.controla_stock loop
    if big_burger.stock_saldo(r.producto, v.dia) is not null then
      insert into big_burger.stock_mov (dia, producto, delta, motivo, venta_id, staff_id) values (v.dia, r.producto, -r.cantidad, 'venta', p_venta, p_staff);
    end if;
  end loop;
end $$;

-- Devuelve al stock lo que descontó una venta que se anula (solo lo que realmente se descontó).
create function big_burger._devolver_stock(p_venta bigint, p_staff uuid) returns void language plpgsql security definer set search_path = '' as $$
declare m record;
begin
  for m in select dia, producto, -delta as cant from big_burger.stock_mov where venta_id = p_venta and motivo = 'venta' loop
    insert into big_burger.stock_mov (dia, producto, delta, motivo, venta_id, staff_id) values (m.dia, m.producto, m.cant, 'anulacion', p_venta, p_staff);
  end loop;
end $$;

-- Comprueba que alcance el stock de una lista de (producto, cantidad). Lanza el mensaje para quien está comprando o vendiendo.
create function big_burger._hay_stock(p_producto text, p_cantidad int, p_dia date) returns void language plpgsql security definer set search_path = '' as $$
declare s int; n text; c boolean;
begin
  select nombre, controla_stock into n, c from big_burger.productos where clave = p_producto;
  s := big_burger.stock_saldo(p_producto, p_dia);
  if c and s is not null and s < p_cantidad then
    raise exception 'No alcanza el stock de %: quedan %.', n, greatest(s, 0);
  end if;
end $$;

-- Motor único de ventas: valida las líneas, calcula precios y totales con los precios de la base (§4.5), numera y guarda.
-- Lo usan venta_registrar (personal) y pedido_crear (web). p_estado 'confirmada' descuenta stock; 'pendiente' solo comprueba que alcance.
create function big_burger._crear_venta(
  p_canal text, p_origen text, p_estado text, p_staff uuid, p_clave text, p_cliente text, p_telefono text, p_sector text,
  p_direccion text, p_maps text, p_nota text, p_programado timestamptz, p_envio int, p_lineas jsonb
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
  insert into big_burger.ventas (dia, numero, canal, origen, estado, clave, staff_id, cliente, telefono, sector, direccion, maps_url, nota, programado,
                                 envio_cent, total_cent, unidades, hamburguesas, resuelto_en)
  values (d, num, p_canal, p_origen, p_estado, p_clave, p_staff, p_cliente, p_telefono, p_sector, p_direccion, p_maps, p_nota, p_programado,
          p_envio, tot + p_envio, uni, burg, case when p_estado = 'confirmada' then now() end)
  returning id into id_v;
  insert into big_burger.venta_lineas (venta_id, producto, nombre, cantidad, precio_cent, cuenta_burger)
    select id_v, t.producto, p.nombre, t.cantidad, p.precio_cent, p.cuenta_burger
    from jsonb_to_recordset(lineas) as t (producto text, cantidad int) join big_burger.productos p on p.clave = t.producto;
  if p_estado = 'confirmada' then perform big_burger._descontar_stock(id_v, p_staff); end if;
  return id_v;
end $$;

-- ---------- funciones públicas (anon) ----------
create function big_burger.ping() returns json language sql stable security definer set search_path = '' as $$
  select json_build_object('ok', true, 'hora', now(), 'dia', big_burger.hoy_ec()) $$;

-- La vitrina y el pedido: productos activos con lo que queda hoy (null = sin dato), sectores de entrega y estado del día.
create function big_burger.carta() returns json language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'hoy', big_burger.hoy_ec(),
    'productos', coalesce((select json_agg(json_build_object(
        'clave', p.clave, 'nombre', p.nombre, 'categoria', p.categoria, 'precio_cent', p.precio_cent, 'lema', p.lema,
        'ingredientes', p.ingredientes, 'foto', p.foto, 'cuenta_burger', p.cuenta_burger,
        'quedan', case when p.controla_stock then big_burger.stock_saldo(p.clave, big_burger.hoy_ec()) end,
        'agotado', p.controla_stock and coalesce(big_burger.stock_saldo(p.clave, big_burger.hoy_ec()), 1) <= 0) order by p.orden, p.nombre)
      from big_burger.productos p where p.activo), '[]'::json),
    'sectores', coalesce((select json_agg(json_build_object('nombre', s.nombre, 'costo_cent', s.costo_cent) order by s.orden, s.nombre)
      from big_burger.sectores s where s.activo), '[]'::json)) $$;

-- Pedido de la web (llevar o domicilio). Nace PENDIENTE: no descuenta stock hasta que el personal lo confirma, así un pedido falso no vacía el stock.
-- p_maps es el enlace de ubicación de Google Maps del cliente (integración de Premium); solo se aceptan enlaces de Google Maps.
create function big_burger.pedido_crear(
  p_nombre text, p_telefono text, p_canal text, p_sector text, p_direccion text, p_maps text, p_nota text, p_programado timestamptz, p_lineas jsonb
) returns json language plpgsql security definer set search_path = '' as $$
declare
  t text := big_burger.tel(p_telefono); c big_burger.config; envio int := 0; sec text := null; dir text := null; maps text := nullif(trim(coalesce(p_maps, '')), '');
  id_v bigint; v big_burger.ventas;
begin
  select * into c from big_burger.config where id = 1;
  if length(trim(coalesce(p_nombre, ''))) < 2 or length(p_nombre) > 80 then raise exception 'Escribe tu nombre.'; end if;
  if t = '' then raise exception 'Escribe un celular válido (09XXXXXXXX).'; end if;
  if p_canal not in ('llevar', 'domicilio') then raise exception 'Elige para llevar o a domicilio.'; end if;
  if length(coalesce(p_nota, '')) > 200 then raise exception 'La nota es muy larga.'; end if;
  if p_programado is not null and (p_programado < now() or p_programado > now() + interval '3 days') then
    raise exception 'La hora programada debe ser dentro de los próximos 3 días.';
  end if;
  if p_canal = 'domicilio' then
    select costo_cent, nombre into envio, sec from big_burger.sectores where nombre = p_sector and activo;
    if sec is null then raise exception 'Elige un sector de entrega.'; end if;
    dir := trim(coalesce(p_direccion, ''));
    if length(dir) < 5 or length(dir) > 200 then raise exception 'Escribe tu dirección.'; end if;
    if maps is not null and maps !~ '^https://(www\.google\.com/maps|maps\.google\.com|maps\.app\.goo\.gl|goo\.gl/maps)([/?#].*)?$' then
      raise exception 'La ubicación debe ser un enlace de Google Maps.';
    end if;
  else
    maps := null;
  end if;
  -- límites de frecuencia (§4.4, §4.8): por teléfono y global
  if (select count(*) from big_burger.ventas where origen = 'web' and telefono = t and creado > now() - interval '1 hour') >= c.max_pedidos_hora_tel then
    raise exception 'Ya enviaste varios pedidos. Espera un momento o escríbenos por WhatsApp.';
  end if;
  if (select count(*) from big_burger.ventas where origen = 'web' and creado > now() - interval '1 hour') >= c.max_pedidos_hora then
    raise exception 'Estamos recibiendo muchos pedidos. Inténtalo en unos minutos o escríbenos por WhatsApp.';
  end if;
  id_v := big_burger._crear_venta(p_canal, 'web', 'pendiente', null, null, trim(p_nombre), t, sec, dir, maps, nullif(trim(coalesce(p_nota, '')), ''), p_programado, envio, p_lineas);
  select * into v from big_burger.ventas where id = id_v;
  return json_build_object('numero', v.numero, 'dia', v.dia, 'total_cent', v.total_cent, 'envio_cent', v.envio_cent);
end $$;

-- Contador público «hamburguesas vendidas este año» (el de la página). Solo existe si el dueño lo activó (config.contador_publico); si no, no devuelve cifras.
create function big_burger.contador() returns json language sql stable security definer set search_path = '' as $$
  select case when (select contador_publico from big_burger.config where id = 1)
    then json_build_object('visible', true, 'anio', extract(year from big_burger.hoy_ec())::int,
      'hamburguesas', (select coalesce(sum(hamburguesas), 0)::int from big_burger.ventas where estado = 'confirmada' and dia >= date_trunc('year', big_burger.hoy_ec())::date))
    else json_build_object('visible', false) end $$;

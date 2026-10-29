-- big-burger · instalación completa del módulo 'restaurante' en Supabase (schema big_burger). Pegar entero en SQL Editor y ejecutar UNA sola vez.
-- Generado por scripts/migraciones-modulo.py restaurante big-burger --instalador desde supabase/migrations/. No editar aquí: editar las migraciones.
-- Proyecto compartido: si el schema ya existe se detiene sin tocar nada (un «already exists» casi siempre es una segunda ejecución).
do $$ begin
  if exists (select 1 from pg_namespace where nspname = 'big_burger') then
    raise exception 'El schema big_burger ya existe: no se instala encima. Si es una actualización, corre solo la migración nueva.';
  end if;
end $$;

-- ===== 001_esquema.sql =====
-- Módulo de restaurante / hamburguesería · 001 esquema.
-- Se aplica con scripts/migraciones-modulo.py restaurante <cliente>, que reemplaza big_burger por el schema del cliente (ej.: gorila_burgers).
-- Qué resuelve: el dueño fija el stock del día, el personal registra cada venta del local, los pedidos de la web quedan guardados y
-- el dueño ve todo en un dashboard casi en tiempo real. Origen: Gorila Burgers (plan Premium).
-- Reglas de CLAUDE.md §4: RLS en todas las tablas y SIN políticas (anon/authenticated nunca leen ni escriben tablas directo: todo pasa por funciones).
-- El valor (precios, totales, envío, stock) se calcula SIEMPRE aquí, nunca en el navegador (§4.5). Los movimientos son inmutables: se corrigen anulando (§4.9).
create schema if not exists big_burger;

create table big_burger.config (
  id int primary key default 1 check (id = 1),
  max_ventas_hora_personal int not null default 300 check (max_ventas_hora_personal between 1 and 2000),   -- tope por empleado y hora
  max_pedidos_hora int not null default 60 check (max_pedidos_hora between 1 and 1000),                      -- pedidos de la web por hora (todos)
  max_pedidos_hora_tel int not null default 3 check (max_pedidos_hora_tel between 1 and 30),                 -- pedidos de la web por teléfono y hora
  max_unidades_linea int not null default 20 check (max_unidades_linea between 1 and 100),
  anular_minutos int not null default 10 check (anular_minutos between 0 and 120),                           -- el empleado anula su propia venta hasta N minutos después
  stock_bajo int not null default 5 check (stock_bajo between 0 and 100),                                     -- aviso de "quedan pocas"
  contador_publico boolean not null default false                                                            -- la página muestra «hamburguesas vendidas este año» solo si el dueño lo activa
);
insert into big_burger.config default values;

-- Personal. admin = dueño (todo). vendedor = empleado (registra ventas, resuelve pedidos, ve el stock; no ve el dashboard ni cambia precios).
create table big_burger.staff (
  user_id uuid primary key references auth.users (id) on delete cascade,
  nombre text not null check (length(trim(nombre)) >= 2),
  rol text not null check (rol in ('admin', 'vendedor')),
  activo boolean not null default true
);

create table big_burger.productos (
  clave text primary key check (clave ~ '^[a-z0-9-]{2,30}$'),
  nombre text not null check (length(trim(nombre)) >= 2),
  categoria text not null default 'burgers' check (length(trim(categoria)) >= 2),
  precio_cent int not null check (precio_cent > 0 and precio_cent <= 100000),
  lema text,                                  -- frase corta que destaca la calidad (ej.: «La campeona que domina»)
  ingredientes text,                          -- lo que lleva, para la vitrina de la página
  foto text,                                  -- ruta en la página (assets/...), no se sube nada a la base
  cuenta_burger boolean not null default true, -- suma al contador de «hamburguesas vendidas» (las bebidas y las papas no)
  controla_stock boolean not null default true,
  activo boolean not null default true,
  orden int not null default 0
);

-- Zonas de entrega a domicilio. Gorila cubre todo Ambato; el costo por sector lo confirma el cliente.
create table big_burger.sectores (
  nombre text primary key check (length(trim(nombre)) >= 2),
  costo_cent int not null default 0 check (costo_cent between 0 and 2000),
  activo boolean not null default true,
  orden int not null default 0
);

-- Ventas del local (canal 'local', las registra el personal) y pedidos de la web (canal 'llevar' o 'domicilio', nacen 'pendiente').
create table big_burger.ventas (
  id bigint generated always as identity primary key,
  dia date not null default ((now() at time zone 'America/Guayaquil')::date),
  numero int not null,                                    -- consecutivo del día (#1, #2, …)
  canal text not null check (canal in ('local', 'llevar', 'domicilio')),
  origen text not null check (origen in ('staff', 'web')),
  estado text not null default 'confirmada' check (estado in ('pendiente', 'confirmada', 'rechazada', 'anulada')),
  clave text,                                             -- evita registrar dos veces la misma venta si se toca dos veces el botón
  staff_id uuid references auth.users (id) on delete set null,
  cliente text check (cliente is null or length(trim(cliente)) between 2 and 80),
  telefono text check (telefono is null or telefono ~ '^593[0-9]{9}$'),   -- normalizado 593XXXXXXXXX (§4.12)
  sector text,
  direccion text check (direccion is null or length(direccion) <= 200),
  maps_url text check (maps_url is null or length(maps_url) <= 300),      -- ubicación del cliente en Google Maps (integración de Premium)
  nota text check (nota is null or length(nota) <= 200),
  programado timestamptz,
  envio_cent int not null default 0 check (envio_cent >= 0),
  total_cent int not null default 0 check (total_cent >= 0),
  unidades int not null default 0 check (unidades >= 0),
  hamburguesas int not null default 0 check (hamburguesas >= 0),
  creado timestamptz not null default now(),
  resuelto_en timestamptz,
  anulado_por uuid references auth.users (id) on delete set null,
  anulado_en timestamptz,
  anulado_motivo text check (anulado_motivo is null or length(anulado_motivo) <= 200),
  unique (dia, numero),
  check ((origen = 'staff' and canal = 'local') or (origen = 'web' and canal in ('llevar', 'domicilio')))
);
create unique index ventas_clave_idx on big_burger.ventas (staff_id, clave) where clave is not null;
create index ventas_dia_idx on big_burger.ventas (dia, estado);
create index ventas_web_idx on big_burger.ventas (telefono, creado) where origen = 'web';

create table big_burger.venta_lineas (
  id bigint generated always as identity primary key,
  venta_id bigint not null references big_burger.ventas (id) on delete cascade,
  producto text not null references big_burger.productos (clave),
  nombre text not null,                                   -- foto del nombre y del precio al momento de la venta
  cantidad int not null check (cantidad between 1 and 100),
  precio_cent int not null check (precio_cent > 0),
  cuenta_burger boolean not null default true
);
create index venta_lineas_venta_idx on big_burger.venta_lineas (venta_id);

-- Stock del día: libro de movimientos inmutable. Saldo = suma de los movimientos del día.
create table big_burger.stock_mov (
  id bigint generated always as identity primary key,
  dia date not null default ((now() at time zone 'America/Guayaquil')::date),
  producto text not null references big_burger.productos (clave),
  delta int not null check (delta <> 0 or motivo in ('carga', 'ajuste')),   -- un 0 solo sirve para marcar «stock del día cargado en cero»
  motivo text not null check (motivo in ('carga', 'ajuste', 'venta', 'anulacion')),
  venta_id bigint references big_burger.ventas (id),
  staff_id uuid references auth.users (id) on delete set null,
  creado timestamptz not null default now()
);
create index stock_mov_idx on big_burger.stock_mov (dia, producto);

-- ---------- inmutabilidad (§4.9) ----------
create function big_burger._solo_insertar() returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'Este registro no se modifica ni se borra: se corrige con una anulación.'; end $$;
create trigger stock_mov_inmutable before update or delete on big_burger.stock_mov for each row execute function big_burger._solo_insertar();
create trigger venta_lineas_inmutable before update or delete on big_burger.venta_lineas for each row execute function big_burger._solo_insertar();

-- Una venta solo cambia de estado: pendiente → confirmada/rechazada, confirmada → anulada. Nada más y nunca se borra.
create function big_burger._venta_estado() returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'Las ventas no se borran: se anulan.'; end if;
  if old.estado = 'pendiente' and new.estado in ('confirmada', 'rechazada')
     and (old.id, old.dia, old.numero, old.canal, old.origen, old.clave, old.cliente, old.telefono, old.sector, old.direccion, old.maps_url, old.nota,
          old.programado, old.envio_cent, old.total_cent, old.unidades, old.hamburguesas, old.creado, old.anulado_por, old.anulado_en, old.anulado_motivo)
         is not distinct from
         (new.id, new.dia, new.numero, new.canal, new.origen, new.clave, new.cliente, new.telefono, new.sector, new.direccion, new.maps_url, new.nota,
          new.programado, new.envio_cent, new.total_cent, new.unidades, new.hamburguesas, new.creado, new.anulado_por, new.anulado_en, new.anulado_motivo) then
    return new;
  end if;
  if old.estado = 'confirmada' and new.estado = 'anulada'
     and (old.id, old.dia, old.numero, old.canal, old.origen, old.clave, old.staff_id, old.cliente, old.telefono, old.sector, old.direccion, old.maps_url, old.nota,
          old.programado, old.envio_cent, old.total_cent, old.unidades, old.hamburguesas, old.creado, old.resuelto_en)
         is not distinct from
         (new.id, new.dia, new.numero, new.canal, new.origen, new.clave, new.staff_id, new.cliente, new.telefono, new.sector, new.direccion, new.maps_url, new.nota,
          new.programado, new.envio_cent, new.total_cent, new.unidades, new.hamburguesas, new.creado, new.resuelto_en) then
    return new;
  end if;
  raise exception 'Una venta solo cambia de estado (pendiente → confirmada o rechazada; confirmada → anulada).';
end $$;
create trigger ventas_estado before update or delete on big_burger.ventas for each row execute function big_burger._venta_estado();

-- RLS en TODAS las tablas y sin políticas: nadie lee ni escribe directo (§4.1, §4.2).
alter table big_burger.config enable row level security;
alter table big_burger.staff enable row level security;
alter table big_burger.productos enable row level security;
alter table big_burger.sectores enable row level security;
alter table big_burger.ventas enable row level security;
alter table big_burger.venta_lineas enable row level security;
alter table big_burger.stock_mov enable row level security;
revoke all on all tables in schema big_burger from public, anon, authenticated;
alter default privileges in schema big_burger revoke all on tables from public, anon, authenticated;

-- ===== 002_funciones_base.sql =====
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

-- ===== 003_funciones_personal.sql =====
-- Módulo de restaurante · 003 funciones del personal (authenticated). Cada una comprueba el rol por dentro (es_staff / es_admin).
-- Empleado (vendedor): registra ventas, anula las suyas dentro del plazo, resuelve pedidos de la web y ve el stock.
-- Dueño (admin): además fija el stock del día, anula cualquier venta, ve el dashboard y cambia carta, sectores y equipo (004).

create function big_burger.yo() returns json language plpgsql stable security definer set search_path = '' as $$
declare s big_burger.staff;
begin
  select * into s from big_burger.staff where user_id = auth.uid() and activo;
  if not found then raise exception 'Esta cuenta no tiene acceso al local.'; end if;
  return json_build_object('nombre', s.nombre, 'rol', s.rol, 'dia', big_burger.hoy_ec());
end $$;

-- Productos de hoy con lo vendido y lo que queda (quedan = null: el dueño aún no cargó el stock de ese producto).
create function big_burger.stock_hoy() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  return coalesce((select json_agg(json_build_object(
      'clave', p.clave, 'nombre', p.nombre, 'categoria', p.categoria, 'precio_cent', p.precio_cent, 'cuenta_burger', p.cuenta_burger,
      'controla_stock', p.controla_stock, 'vendidas', big_burger.vendidas(p.clave, big_burger.hoy_ec()),
      'quedan', case when p.controla_stock then big_burger.stock_saldo(p.clave, big_burger.hoy_ec()) end,
      'inicial', case when p.controla_stock and big_burger.stock_saldo(p.clave, big_burger.hoy_ec()) is not null
                      then big_burger.stock_saldo(p.clave, big_burger.hoy_ec()) + big_burger.vendidas(p.clave, big_burger.hoy_ec()) end) order by p.orden, p.nombre)
    from big_burger.productos p where p.activo), '[]'::json);
end $$;

-- Una venta del local. p_clave evita duplicarla si se toca dos veces el botón. Precios, total y stock los calcula la base (§4.5).
create function big_burger.venta_registrar(p_lineas jsonb, p_clave text default null, p_nota text default null) returns json language plpgsql security definer set search_path = '' as $$
declare c big_burger.config; v big_burger.ventas; id_v bigint; k text := nullif(trim(coalesce(p_clave, '')), '');
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  if k is not null and length(k) > 60 then raise exception 'Clave no válida.'; end if;
  if length(coalesce(p_nota, '')) > 200 then raise exception 'La nota es muy larga.'; end if;
  select * into v from big_burger.ventas where staff_id = auth.uid() and clave = k;
  if found then
    return json_build_object('id', v.id, 'numero', v.numero, 'total_cent', v.total_cent, 'unidades', v.unidades, 'repetida', true);
  end if;
  select * into c from big_burger.config where id = 1;
  if (select count(*) from big_burger.ventas where staff_id = auth.uid() and origen = 'staff' and creado > now() - interval '1 hour') >= c.max_ventas_hora_personal then
    raise exception 'Demasiadas ventas en una hora. Avisa al dueño.';
  end if;
  id_v := big_burger._crear_venta('local', 'staff', 'confirmada', auth.uid(), k, null, null, null, null, null, nullif(trim(coalesce(p_nota, '')), ''), null, 0, p_lineas);
  select * into v from big_burger.ventas where id = id_v;
  return json_build_object('id', v.id, 'numero', v.numero, 'total_cent', v.total_cent, 'unidades', v.unidades, 'repetida', false);
end $$;

-- Anular una venta confirmada (error de dedo, cliente que se arrepintió). El empleado solo anula las suyas durante config.anular_minutos; el dueño, cualquiera.
create function big_burger.venta_anular(p_id bigint, p_motivo text) returns void language plpgsql security definer set search_path = '' as $$
declare v big_burger.ventas; plazo int := (select anular_minutos from big_burger.config where id = 1);
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  if length(trim(coalesce(p_motivo, ''))) < 3 or length(p_motivo) > 200 then raise exception 'Escribe el motivo de la anulación.'; end if;
  perform pg_advisory_xact_lock(hashtext('big_burger.ventas'));
  select * into v from big_burger.ventas where id = p_id for update;
  if not found then raise exception 'No existe esa venta.'; end if;
  if v.estado <> 'confirmada' then raise exception 'Esa venta ya no se puede anular.'; end if;
  if not big_burger.es_admin() and (v.staff_id is distinct from auth.uid() or now() - coalesce(v.resuelto_en, v.creado) > make_interval(mins => plazo)) then
    raise exception 'Solo el dueño puede anular esta venta (el plazo del empleado es de % minutos y solo para sus ventas).', plazo;
  end if;
  update big_burger.ventas set estado = 'anulada', anulado_por = auth.uid(), anulado_en = now(), anulado_motivo = trim(p_motivo) where id = p_id;
  perform big_burger._devolver_stock(p_id, auth.uid());
end $$;

-- Ventas de hoy. El empleado ve las suyas; el dueño, todas.
create function big_burger.ventas_hoy() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  return coalesce((select json_agg(x order by (x->>'id')::bigint desc) from (
    select json_build_object('id', v.id, 'numero', v.numero, 'canal', v.canal, 'estado', v.estado, 'total_cent', v.total_cent, 'unidades', v.unidades,
        'creado', v.creado, 'quien', s.nombre, 'puede_anular', v.estado = 'confirmada' and (big_burger.es_admin()
           or (v.staff_id = auth.uid() and now() - coalesce(v.resuelto_en, v.creado) <= make_interval(mins => (select anular_minutos from big_burger.config where id = 1)))),
        'lineas', (select json_agg(json_build_object('nombre', l.nombre, 'cantidad', l.cantidad) order by l.id) from big_burger.venta_lineas l where l.venta_id = v.id)) as x
    from big_burger.ventas v left join big_burger.staff s on s.user_id = v.staff_id
    where v.dia = big_burger.hoy_ec() and v.estado in ('confirmada', 'anulada') and (big_burger.es_admin() or v.staff_id = auth.uid())
    order by v.id desc limit 100) t), '[]'::json);
end $$;

-- Pedidos de la web que esperan respuesta del local. Los de días anteriores salen como vencidos: solo se pueden rechazar.
create function big_burger.pedidos_pendientes() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  return coalesce((select json_agg(x order by (x->>'id')::bigint) from (
    select json_build_object('id', v.id, 'numero', v.numero, 'canal', v.canal, 'cliente', v.cliente, 'telefono', v.telefono, 'sector', v.sector,
        'direccion', v.direccion, 'maps_url', v.maps_url, 'nota', v.nota, 'programado', v.programado, 'envio_cent', v.envio_cent, 'total_cent', v.total_cent,
        'unidades', v.unidades, 'creado', v.creado, 'vencido', v.dia <> big_burger.hoy_ec(),
        'lineas', (select json_agg(json_build_object('nombre', l.nombre, 'cantidad', l.cantidad) order by l.id) from big_burger.venta_lineas l where l.venta_id = v.id)) as x
    from big_burger.ventas v where v.estado = 'pendiente' order by v.id limit 60) t), '[]'::json);
end $$;

-- Confirmar (la burger entra a cocina: cuenta como vendida y descuenta stock) o rechazar un pedido de la web.
create function big_burger.pedido_resolver(p_id bigint, p_accion text) returns void language plpgsql security definer set search_path = '' as $$
declare v big_burger.ventas; l record;
begin
  if not big_burger.es_staff() then raise exception 'Solo el personal.'; end if;
  if p_accion not in ('confirmar', 'rechazar') then raise exception 'Acción no válida.'; end if;
  perform pg_advisory_xact_lock(hashtext('big_burger.ventas'));
  select * into v from big_burger.ventas where id = p_id for update;
  if not found or v.origen <> 'web' then raise exception 'No existe ese pedido.'; end if;
  if v.estado <> 'pendiente' then raise exception 'Ese pedido ya fue resuelto.'; end if;
  if p_accion = 'rechazar' then
    update big_burger.ventas set estado = 'rechazada', staff_id = auth.uid(), resuelto_en = now() where id = p_id;
    return;
  end if;
  if v.dia <> big_burger.hoy_ec() then raise exception 'Este pedido es de otro día: solo se puede rechazar.'; end if;
  for l in select producto, cantidad from big_burger.venta_lineas where venta_id = p_id loop
    perform big_burger._hay_stock(l.producto, l.cantidad, v.dia);
  end loop;
  update big_burger.ventas set estado = 'confirmada', staff_id = auth.uid(), resuelto_en = now() where id = p_id;
  perform big_burger._descontar_stock(p_id, auth.uid());
end $$;

-- ---------- stock del día (dueño) ----------
-- p_cantidad = cuántas hay para HOY en total (lo que ya se vendió cuenta dentro). Si el dueño la corrige, se registra un ajuste.
create function big_burger._stock_fijar(p_prod text, p_cant int, p_staff uuid) returns json language plpgsql security definer set search_path = '' as $$
declare d date := big_burger.hoy_ec(); vend int; saldo int; objetivo int; p big_burger.productos;
begin
  select * into p from big_burger.productos where clave = p_prod and activo;
  if not found then raise exception 'No existe ese producto.'; end if;
  if not p.controla_stock then raise exception '% no lleva control de stock.', p.nombre; end if;
  if p_cant is null or p_cant < 0 or p_cant > 9999 then raise exception 'La cantidad debe estar entre 0 y 9999.'; end if;
  vend := big_burger.vendidas(p_prod, d);
  if p_cant < vend then raise exception 'Ya se vendieron % de % hoy: el stock del día no puede ser menor.', vend, p.nombre; end if;
  saldo := big_burger.stock_saldo(p_prod, d);
  objetivo := p_cant - vend;
  insert into big_burger.stock_mov (dia, producto, delta, motivo, staff_id)
    values (d, p_prod, objetivo - coalesce(saldo, 0), case when saldo is null then 'carga' else 'ajuste' end, p_staff);
  return json_build_object('producto', p_prod, 'inicial', p_cant, 'quedan', objetivo);
end $$;

create function big_burger.stock_fijar(p_producto text, p_cantidad int) returns json language plpgsql security definer set search_path = '' as $$
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño fija el stock.'; end if;
  perform pg_advisory_xact_lock(hashtext('big_burger.ventas'));
  return big_burger._stock_fijar(p_producto, p_cantidad, auth.uid());
end $$;

-- Varias a la vez: [{"producto": "texas", "cantidad": 40}, …]. Todo o nada.
create function big_burger.stock_fijar_varios(p_items jsonb) returns json language plpgsql security definer set search_path = '' as $$
declare r record; salida jsonb := '[]'::jsonb;
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño fija el stock.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 60 then raise exception 'Lista de stock no válida.'; end if;
  perform pg_advisory_xact_lock(hashtext('big_burger.ventas'));
  for r in select * from jsonb_to_recordset(p_items) as x (producto text, cantidad int) loop
    salida := salida || jsonb_build_array(big_burger._stock_fijar(r.producto, r.cantidad, auth.uid()));
  end loop;
  return salida::json;
end $$;

-- ===== 004_dashboard_admin.sql =====
-- Módulo de restaurante · 004 dashboard del dueño, reporte mensual y administración (solo admin).
-- El dashboard se lee por función (no hay lectura directa de tablas, §4.2): la página la consulta cada pocos segundos y se ve «en vivo».

create function big_burger.dashboard() returns json language plpgsql stable security definer set search_path = '' as $$
declare
  d date := big_burger.hoy_ec();
  ahora timestamp := now() at time zone 'America/Guayaquil';
  c big_burger.config;
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño ve el dashboard.'; end if;
  select * into c from big_burger.config where id = 1;
  return json_build_object(
    'generado', now(), 'dia', d, 'hora', extract(hour from ahora)::int, 'stock_bajo', c.stock_bajo,
    -- lo de hoy
    'resumen', (select json_build_object(
        'ventas', count(*), 'unidades', coalesce(sum(unidades), 0), 'hamburguesas', coalesce(sum(hamburguesas), 0),
        'ingresos_cent', coalesce(sum(total_cent - envio_cent), 0), 'envios_cent', coalesce(sum(envio_cent), 0),
        'ticket_cent', coalesce(round(sum(total_cent - envio_cent)::numeric / nullif(count(*), 0)), 0)::int,
        'local', coalesce(sum(hamburguesas) filter (where canal = 'local'), 0),
        'llevar', coalesce(sum(hamburguesas) filter (where canal = 'llevar'), 0),
        'domicilio', coalesce(sum(hamburguesas) filter (where canal = 'domicilio'), 0),
        'ingresos_local_cent', coalesce(sum(total_cent - envio_cent) filter (where canal = 'local'), 0),
        'ingresos_web_cent', coalesce(sum(total_cent - envio_cent) filter (where canal <> 'local'), 0))
      from big_burger.ventas where dia = d and estado = 'confirmada'),
    'anuladas', (select json_build_object('n', count(*), 'total_cent', coalesce(sum(total_cent), 0)) from big_burger.ventas where dia = d and estado = 'anulada'),
    'pendientes', (select count(*) from big_burger.ventas where estado = 'pendiente' and dia = d),
    -- mismo día de la semana pasada: hasta esta hora y completo
    'semana_pasada', (select json_build_object(
        'hamburguesas_ahora', coalesce(sum(hamburguesas) filter (where (creado at time zone 'America/Guayaquil') <= ahora - interval '7 days'), 0),
        'hamburguesas_dia', coalesce(sum(hamburguesas), 0), 'ingresos_dia_cent', coalesce(sum(total_cent - envio_cent), 0))
      from big_burger.ventas where dia = d - 7 and estado = 'confirmada'),
    -- hamburguesas por hora, hoy y el mismo día de la semana pasada
    'por_hora', (select json_agg(json_build_object('h', g, 'hamburguesas', coalesce(a.n, 0), 'anterior', coalesce(b.n, 0)) order by g)
      from generate_series(0, 23) g
      left join (select extract(hour from creado at time zone 'America/Guayaquil')::int h, sum(hamburguesas)::int n from big_burger.ventas
                 where dia = d and estado = 'confirmada' group by 1) a on a.h = g
      left join (select extract(hour from creado at time zone 'America/Guayaquil')::int h, sum(hamburguesas)::int n from big_burger.ventas
                 where dia = d - 7 and estado = 'confirmada' group by 1) b on b.h = g),
    -- cada producto: vendidas, ingresos y stock (estado: ok · bajo · agotado · sin_definir · libre)
    'productos', (select coalesce(json_agg(json_build_object(
        'clave', x.clave, 'nombre', x.nombre, 'categoria', x.categoria, 'cuenta_burger', x.cuenta_burger, 'precio_cent', x.precio_cent,
        'vendidas', x.vendidas, 'ingresos_cent', x.ingresos, 'quedan', x.saldo,
        'inicial', case when x.saldo is not null then x.saldo + x.vendidas end,
        'estado', case when not x.controla_stock then 'libre' when x.saldo is null then 'sin_definir' when x.saldo <= 0 then 'agotado'
                       when x.saldo <= c.stock_bajo then 'bajo' else 'ok' end) order by x.vendidas desc, x.orden, x.nombre), '[]'::json)
      from (select p.*, coalesce(s.cant, 0)::int as vendidas, coalesce(s.ing, 0)::int as ingresos,
                   case when p.controla_stock then big_burger.stock_saldo(p.clave, d) end as saldo
            from big_burger.productos p
            left join (select l.producto, sum(l.cantidad) cant, sum(l.cantidad * l.precio_cent) ing from big_burger.venta_lineas l
                       join big_burger.ventas vv on vv.id = l.venta_id where vv.dia = d and vv.estado = 'confirmada' group by 1) s on s.producto = p.clave
            where p.activo) x),
    -- quién vendió en el local
    'equipo', (select coalesce(json_agg(json_build_object('nombre', n.nombre, 'ventas', n.ventas, 'hamburguesas', n.burgers, 'ingresos_cent', n.ing) order by n.burgers desc), '[]'::json)
      from (select s.nombre, count(*)::int ventas, sum(v.hamburguesas)::int burgers, sum(v.total_cent)::int ing
            from big_burger.ventas v join big_burger.staff s on s.user_id = v.staff_id
            where v.dia = d and v.estado = 'confirmada' and v.origen = 'staff' group by s.nombre) n),
    -- últimos movimientos (venta o anulación)
    'ultimas', (select coalesce(json_agg(u order by (u->>'id')::bigint desc), '[]'::json) from (
        select json_build_object('id', v.id, 'numero', v.numero, 'canal', v.canal, 'estado', v.estado, 'total_cent', v.total_cent, 'unidades', v.unidades,
            'creado', v.creado, 'quien', s.nombre, 'cliente', v.cliente, 'sector', v.sector,
            'lineas', (select json_agg(json_build_object('nombre', l.nombre, 'cantidad', l.cantidad) order by l.id) from big_burger.venta_lineas l where l.venta_id = v.id)) as u
        from big_burger.ventas v left join big_burger.staff s on s.user_id = v.staff_id
        where v.dia = d and v.estado in ('confirmada', 'anulada') order by v.id desc limit 15) t),
    -- últimos 7 días (con hoy)
    'semana', (select json_agg(json_build_object('dia', g::date, 'hamburguesas', coalesce(a.n, 0), 'ingresos_cent', coalesce(a.ing, 0), 'ventas', coalesce(a.v, 0)) order by g)
      from generate_series(d - 6, d, interval '1 day') g
      left join (select dia, sum(hamburguesas)::int n, sum(total_cent - envio_cent)::int ing, count(*)::int v from big_burger.ventas
                 where dia between d - 6 and d and estado = 'confirmada' group by dia) a on a.dia = g::date),
    -- récord de los últimos 90 días
    'record', (select json_build_object('dia', dia, 'hamburguesas', n) from (
        select dia, sum(hamburguesas)::int n from big_burger.ventas where dia between d - 90 and d - 1 and estado = 'confirmada' group by dia order by n desc limit 1) r));
end $$;

-- Reporte mensual (Premium): lo que Cowork usa para armar el reporte del mes. p_mes = cualquier día del mes (por defecto, el mes actual).
create function big_burger.reporte_mes(p_mes date default null) returns json language plpgsql stable security definer set search_path = '' as $$
declare m0 date := date_trunc('month', coalesce(p_mes, big_burger.hoy_ec()))::date; m1 date; a0 date;
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño ve el reporte.'; end if;
  m1 := (m0 + interval '1 month')::date; a0 := (m0 - interval '1 month')::date;
  return json_build_object(
    'mes', m0,
    'resumen', (select json_build_object('ventas', count(*), 'unidades', coalesce(sum(unidades), 0), 'hamburguesas', coalesce(sum(hamburguesas), 0),
        'ingresos_cent', coalesce(sum(total_cent - envio_cent), 0), 'envios_cent', coalesce(sum(envio_cent), 0),
        'ticket_cent', coalesce(round(sum(total_cent - envio_cent)::numeric / nullif(count(*), 0)), 0)::int,
        'dias_con_ventas', count(distinct dia),
        'promedio_diario', coalesce(round(sum(hamburguesas)::numeric / nullif(count(distinct dia), 0), 1), 0))
      from big_burger.ventas where dia >= m0 and dia < m1 and estado = 'confirmada'),
    'mes_anterior', (select json_build_object('hamburguesas', coalesce(sum(hamburguesas), 0), 'ingresos_cent', coalesce(sum(total_cent - envio_cent), 0))
      from big_burger.ventas where dia >= a0 and dia < m0 and estado = 'confirmada'),
    'por_dia', (select coalesce(json_agg(json_build_object('dia', dia, 'hamburguesas', n, 'ingresos_cent', ing) order by dia), '[]'::json)
      from (select dia, sum(hamburguesas)::int n, sum(total_cent - envio_cent)::int ing from big_burger.ventas
            where dia >= m0 and dia < m1 and estado = 'confirmada' group by dia) t),
    'por_producto', (select coalesce(json_agg(json_build_object('nombre', nombre, 'vendidas', n, 'ingresos_cent', ing) order by n desc), '[]'::json)
      from (select l.nombre, sum(l.cantidad)::int n, sum(l.cantidad * l.precio_cent)::int ing from big_burger.venta_lineas l
            join big_burger.ventas v on v.id = l.venta_id where v.dia >= m0 and v.dia < m1 and v.estado = 'confirmada' group by l.nombre) t),
    'por_canal', (select coalesce(json_agg(json_build_object('canal', canal, 'ventas', ventas, 'hamburguesas', n, 'ingresos_cent', ing)), '[]'::json)
      from (select canal, count(*)::int ventas, sum(hamburguesas)::int n, sum(total_cent - envio_cent)::int ing from big_burger.ventas
            where dia >= m0 and dia < m1 and estado = 'confirmada' group by canal) t),
    'por_sector', (select coalesce(json_agg(json_build_object('sector', sector, 'pedidos', n) order by n desc), '[]'::json)
      from (select sector, count(*)::int n from big_burger.ventas where dia >= m0 and dia < m1 and estado = 'confirmada' and canal = 'domicilio' group by sector) t),
    'por_hora', (select coalesce(json_agg(json_build_object('h', h, 'hamburguesas', n) order by h), '[]'::json)
      from (select extract(hour from creado at time zone 'America/Guayaquil')::int h, sum(hamburguesas)::int n from big_burger.ventas
            where dia >= m0 and dia < m1 and estado = 'confirmada' group by 1) t),
    'por_dia_semana', (select coalesce(json_agg(json_build_object('dow', dow, 'hamburguesas', n) order by dow), '[]'::json)
      from (select extract(isodow from dia)::int dow, sum(hamburguesas)::int n from big_burger.ventas
            where dia >= m0 and dia < m1 and estado = 'confirmada' group by 1) t),
    'anuladas', (select json_build_object('n', count(*), 'total_cent', coalesce(sum(total_cent), 0)) from big_burger.ventas where dia >= m0 and dia < m1 and estado = 'anulada'),
    'web', (select json_build_object('recibidos', count(*), 'confirmados', count(*) filter (where estado in ('confirmada', 'anulada')),
        'rechazados', count(*) filter (where estado = 'rechazada'), 'sin_responder', count(*) filter (where estado = 'pendiente'))
      from big_burger.ventas where dia >= m0 and dia < m1 and origen = 'web'));
end $$;

-- ---------- administración (dueño) ----------
create function big_burger.productos_admin() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño.'; end if;
  return coalesce((select json_agg(row_to_json(p) order by p.orden, p.nombre) from big_burger.productos p), '[]'::json);
end $$;

create function big_burger.producto_guardar(
  p_clave text, p_nombre text, p_categoria text, p_precio_cent int, p_lema text, p_ingredientes text, p_foto text,
  p_cuenta_burger boolean, p_controla_stock boolean, p_activo boolean, p_orden int
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño.'; end if;
  if p_foto is not null and p_foto !~ '^assets/[a-z0-9._/-]{1,100}$' then raise exception 'La foto debe ser un archivo de la carpeta assets.'; end if;
  if p_clave !~ '^[a-z0-9-]{2,30}$' then raise exception 'La clave son letras minúsculas, números y guiones.'; end if;
  insert into big_burger.productos (clave, nombre, categoria, precio_cent, lema, ingredientes, foto, cuenta_burger, controla_stock, activo, orden)
  values (p_clave, trim(p_nombre), trim(p_categoria), p_precio_cent, nullif(trim(coalesce(p_lema, '')), ''), nullif(trim(coalesce(p_ingredientes, '')), ''), p_foto,
          coalesce(p_cuenta_burger, true), coalesce(p_controla_stock, true), coalesce(p_activo, true), coalesce(p_orden, 0))
  on conflict (clave) do update set nombre = excluded.nombre, categoria = excluded.categoria, precio_cent = excluded.precio_cent, lema = excluded.lema,
    ingredientes = excluded.ingredientes, foto = excluded.foto, cuenta_burger = excluded.cuenta_burger, controla_stock = excluded.controla_stock,
    activo = excluded.activo, orden = excluded.orden;
end $$;

create function big_burger.sector_guardar(p_nombre text, p_costo_cent int, p_activo boolean default true, p_orden int default 0) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño.'; end if;
  insert into big_burger.sectores (nombre, costo_cent, activo, orden) values (trim(p_nombre), p_costo_cent, coalesce(p_activo, true), coalesce(p_orden, 0))
  on conflict (nombre) do update set costo_cent = excluded.costo_cent, activo = excluded.activo, orden = excluded.orden;
end $$;

create function big_burger.equipo_lista() returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño.'; end if;
  return coalesce((select json_agg(json_build_object('user_id', s.user_id, 'nombre', s.nombre, 'rol', s.rol, 'activo', s.activo, 'correo', u.email) order by s.nombre)
    from big_burger.staff s join auth.users u on u.id = s.user_id), '[]'::json);
end $$;

-- El usuario se crea primero en Supabase › Authentication › Add user (los registros públicos están desactivados, §4.10); luego se le da el rol aquí.
create function big_burger.equipo_guardar(p_correo text, p_nombre text, p_rol text, p_activo boolean default true) returns void language plpgsql security definer set search_path = '' as $$
declare u uuid;
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño.'; end if;
  if p_rol not in ('admin', 'vendedor') then raise exception 'Rol no válido.'; end if;
  select id into u from auth.users where lower(email) = lower(trim(p_correo));
  if u is null then raise exception 'Ese correo no tiene usuario. Créalo primero en Supabase › Authentication › Add user.'; end if;
  if u = auth.uid() and (p_rol <> 'admin' or not coalesce(p_activo, true)) then raise exception 'No puedes quitarte tu propio acceso de dueño.'; end if;
  insert into big_burger.staff (user_id, nombre, rol, activo) values (u, coalesce(nullif(trim(p_nombre), ''), split_part(p_correo, '@', 1)), p_rol, coalesce(p_activo, true))
  on conflict (user_id) do update set nombre = excluded.nombre, rol = excluded.rol, activo = excluded.activo;
end $$;

create function big_burger.config_guardar(p_anular_minutos int, p_stock_bajo int, p_max_ventas_hora_personal int, p_max_pedidos_hora int, p_max_pedidos_hora_tel int)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño.'; end if;
  update big_burger.config set anular_minutos = p_anular_minutos, stock_bajo = p_stock_bajo, max_ventas_hora_personal = p_max_ventas_hora_personal,
    max_pedidos_hora = p_max_pedidos_hora, max_pedidos_hora_tel = p_max_pedidos_hora_tel where id = 1;
end $$;

create function big_burger.contador_publico_guardar(p_visible boolean) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not big_burger.es_admin() then raise exception 'Solo el dueño.'; end if;
  update big_burger.config set contador_publico = coalesce(p_visible, false) where id = 1;
end $$;

-- ===== 005_permisos.sql =====
-- Módulo de restaurante · 005 permisos (§4.3): primero se revoca TODO a public/anon/authenticated y luego se concede solo lo necesario.
-- Postgres concede EXECUTE a PUBLIC por defecto en cada función nueva; por eso el revoke va explícito.
revoke all on all functions in schema big_burger from public, anon, authenticated;
alter default privileges in schema big_burger revoke execute on functions from public, anon, authenticated;
grant usage on schema big_burger to anon, authenticated;

-- El cliente final (sin sesión): solo la vitrina, el contador (si el dueño lo activó) y crear un pedido. Todo se valida dentro.
grant execute on function big_burger.ping(), big_burger.carta(), big_burger.contador(),
  big_burger.pedido_crear(text, text, text, text, text, text, text, timestamptz, jsonb)
to anon, authenticated;

-- El personal y el dueño (con sesión de Authentication): cada función comprueba es_staff() / es_admin() por dentro.
grant execute on function
  big_burger.yo(), big_burger.stock_hoy(), big_burger.venta_registrar(jsonb, text, text), big_burger.venta_anular(bigint, text),
  big_burger.ventas_hoy(), big_burger.pedidos_pendientes(), big_burger.pedido_resolver(bigint, text),
  big_burger.stock_fijar(text, int), big_burger.stock_fijar_varios(jsonb),
  big_burger.dashboard(), big_burger.reporte_mes(date),
  big_burger.productos_admin(),
  big_burger.producto_guardar(text, text, text, int, text, text, text, boolean, boolean, boolean, int),
  big_burger.sector_guardar(text, int, boolean, int),
  big_burger.equipo_lista(), big_burger.equipo_guardar(text, text, text, boolean),
  big_burger.config_guardar(int, int, int, int, int), big_burger.contador_publico_guardar(boolean)
to authenticated;
-- Ayudas internas (tel, hoy_ec, rol, es_*, stock_saldo, vendidas, _descontar_stock, _devolver_stock, _hay_stock, _crear_venta, _stock_fijar, triggers):
-- sin permiso para nadie. Las llaman las funciones de arriba (security definer).

-- ===== 006_semilla.sql =====
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
  ('bebida-jugo', 'Jugo natural', 'bebidas', 150, null, null, null, false, false, true, 12),
  ('x-carne', 'Carne extra 140 g', 'extras', 150, null, null, null, false, false, true, 13),
  ('x-queso', 'Queso cheddar extra', 'extras', 50, null, null, null, false, false, true, 14),
  ('x-tocino', 'Tocino extra', 'extras', 75, null, null, null, false, false, true, 15)
on conflict (clave) do update set nombre = excluded.nombre, categoria = excluded.categoria, precio_cent = excluded.precio_cent, lema = excluded.lema,
  ingredientes = excluded.ingredientes, foto = excluded.foto, cuenta_burger = excluded.cuenta_burger, controla_stock = excluded.controla_stock, orden = excluded.orden;

-- Sin sectores de entrega todavía (solo para llevar). Se agregan después con sector_guardar(nombre, costo_cent, true, orden) o regenerando esta semilla.

-- Primer dueño: crea el usuario en Supabase › Authentication › Add user (o reutiliza el que ya tenga por otro negocio) y luego corre, con su correo.
-- En el proyecto COMPARTIDO el registro público queda encendido a propósito (CLAUDE.md §4.10): no se apaga; el acceso lo da solo la tabla staff de este schema.
--   insert into big_burger.staff (user_id, nombre, rol) select id, 'Dueño', 'admin' from auth.users where lower(email) = lower('CORREO_DEL_DUEÑO');
-- Después el dueño da de alta a sus empleados desde la función equipo_guardar(correo, nombre, 'vendedor').

-- ===== 008_pantalla.sql =====
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

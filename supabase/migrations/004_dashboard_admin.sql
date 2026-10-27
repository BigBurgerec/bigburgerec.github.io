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

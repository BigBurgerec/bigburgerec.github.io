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

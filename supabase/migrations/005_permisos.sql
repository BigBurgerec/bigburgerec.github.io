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

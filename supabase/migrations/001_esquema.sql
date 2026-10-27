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

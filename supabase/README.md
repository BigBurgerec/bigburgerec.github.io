# Big Burger · base de datos (Supabase)

Schema propio **`big_burger`** en el proyecto **compartido** `jukpaqtriemqvxormrgb` (CLAUDE.md §1). Módulo de restaurante (`modulos/restaurante/`) con la pantalla en tienda (migración 008). Ninguna tabla se lee ni se escribe directo: todo pasa por funciones SQL con validación y límites (CLAUDE.md §4).

## Cómo fluye un pedido (estructura de MockaBox)
```
 Página web (index.html) ──┐                          ┌─► Confirmar → cuenta como vendida y descuenta stock
   también abre WhatsApp   ├─► ventas · pendiente ────┤
 Pantalla en tienda ───────┘   (no descuenta stock)   └─► Rechazar → no pasa nada
   (pantalla.html, paga en caja)        ▲
                                        │ la caja la lee cada 6 s y suena un aviso
                                  Caja (personal.html)
```
- Un pedido nunca descuenta stock al enviarse: queda **pendiente**. Al confirmarlo en caja cuenta como vendido.
- Los pendientes **vencen a las 3 horas** (o al cambiar de día): vencidos solo se pueden rechazar.
- Sin tarjeta prepago ni pasarela: la web cobra por WhatsApp o transferencia; la pantalla, en caja.

## Quién puede qué
| Cuenta | Rol | Puede |
|---|---|---|
| Cliente en la web (sin sesión) | `anon` | `carta()`, `contador()`, `pedido_crear()` (límite por celular y por hora) |
| Tablet del local | `pantalla` | Solo `pantalla_yo()` y `pedido_local()` (máx. 30 pedidos cada 10 min). **No** ve caja, ventas, stock ni dashboard |
| Cajero / empleado | `vendedor` | Caja: confirmar o rechazar pedidos, registrar ventas del mostrador, anular las suyas en 10 min, ver stock |
| Dueño | `admin` | Todo: dashboard, stock del día, anular cualquier venta, carta, sectores, equipo, reporte del mes |

## Activar (una sola vez · lo hace Daniel)
El instalador del 27 oct va **sin sectores** (solo para llevar; «a domicilio» está apagado en la web). Cuando lleguen los sectores con su costo se cargan con
`insert into big_burger.sectores (nombre, costo_cent, orden) values ('Nombre del sector', 150, 1);` en el SQL Editor (costo en centavos: 150 = $1.50), y se vuelve a encender «a domicilio» en el sitio.
1. **Confirmar que el schema no existe:** `select 1 from pg_namespace where nspname = 'big_burger';` debe salir vacío.
2. **SQL Editor** → pegar `instalar-todo.sql` completo → **Run una sola vez**. Si el schema ya existe se detiene sin tocar nada.
3. **Comprobar:**
   ```sql
   select (select count(*) from information_schema.tables where table_schema = 'big_burger') tablas,          -- 7
          (select count(*) from pg_proc where pronamespace = 'big_burger'::regnamespace) funciones,          -- 41
          (select count(*) from big_burger.productos) productos;                                            -- 10
   ```
4. **Project Settings → Data API → Exposed schemas:** agregar `big_burger` **sin quitar los demás**.
5. **Authentication → Users → Add user** (con *Auto Confirm User*): el dueño (si ya existe por otro negocio, se reutiliza), cada cajero y **una cuenta para la tablet** (ej. `pantalla@<dominio>`). Luego, en SQL Editor:
   ```sql
   insert into big_burger.staff (user_id, nombre, rol) select id, 'Dueño', 'admin' from auth.users where lower(email) = lower('CORREO_DEL_DUEÑO');
   ```
   Más fácil: pegar `cuentas.sql` con los tres correos reales (dueño `admin`, caja `vendedor`, tablet `pantalla`).
6. **No** se apaga el registro público de Authentication (lo usan otros negocios del proyecto, CLAUDE.md §4.10): una cuenta que no está en `big_burger.staff` no entra a nada.
7. La **clave anon** se pega en `clientes/big-burger/cliente.json` → `restaurante.produccion.api.anonKey` (solo la anon, nunca `service_role`) y se regenera: `python3 scripts/nuevo-cliente.py big-burger --produccion`.
8. **Prueba de humo:** `python3 scripts/probar-supabase.py big-burger` y la checklist corta: pedido web → aparece en caja → confirmar; pedido en la tablet → suena en caja → confirmar; dashboard sube; anular.

## La tablet (pantalla en tienda)
- Abrir `https://<sitio>/pantalla.html` en la tablet, entrar **una vez** con la cuenta de la pantalla y en el menú del navegador tocar **Instalar app / Agregar a la pantalla de inicio**: abre a pantalla completa y en vertical.
- La sesión queda guardada en la tablet. Para cerrarla: mantener presionado el logo de la bienvenida 5 segundos.
- Tras 90 s sin tocar vuelve sola a la bienvenida y borra el carrito y el nombre.

## Probar en local (sin tocar Supabase)
```bash
PGURI=postgresql://postgres@localhost:5432/postgres python3 modulos/restaurante/probar.py      # 221 comprobaciones del módulo (incluye la pantalla)
python3 scripts/nuevo-cliente.py big-burger --produccion
PGURI=… python3 scripts/supabase-local.py big-burger --usuario dueno@x.ec:clave:admin --usuario caja@x.ec:clave:vendedor --usuario pantalla@x.ec:clave:pantalla
# abrir http://localhost:8790/ (página), /pantalla.html (tablet), /personal.html (caja), /dashboard.html (dueño)
```

## Migraciones
`001`–`005` módulo de restaurante · `006_semilla.sql` carta y sectores de Big Burger · `008_pantalla.sql` pantalla en tienda y vencimiento. (`007_juego.sql` no aplica: sin juego con premio.) `instalar-todo.sql` es la unión, para pegar de una vez. Un cambio posterior va en una migración nueva numerada, nunca editando una ya aplicada.

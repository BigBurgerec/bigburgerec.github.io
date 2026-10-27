# Big Burger · Ambato

Sitio de **Big Burger** (hamburguesas premium) publicado con GitHub Pages en https://bigburgerec.github.io/ (publicar = push a `main`).

| Página | Para qué |
|---|---|
| `index.html` | La página: las burgers, la carta y el pedido para llevar o a domicilio (llega a la caja y por WhatsApp) |
| `pantalla.html` | Pantalla del local (tablet): el cliente pide solo y paga en caja |
| `personal.html` | Caja: pedidos de la web y de la pantalla, ventas del mostrador |
| `dashboard.html` | Dashboard del dueño: ventas en vivo y stock del día |

La base de datos vive en Supabase (schema `big_burger`); cómo se activa: `supabase/README.md`. En la web solo va la clave **anon** de Supabase.
Las páginas se generan desde el repositorio de la agencia; los cambios de carta, precios o textos se hacen allá y se vuelven a publicar aquí.

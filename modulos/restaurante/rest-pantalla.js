/* Módulo de restaurante · pantalla en tienda (kiosco). Tablet vertical en el local: el cliente pide solo y paga en caja (estructura de MockaBox).
   Pasos: reposo → menú → tu pedido → confirmación. Tras 90 s sin tocar vuelve a reposo y borra el carrito y los datos.
   La tablet entra UNA vez con su cuenta de Authentication (rol 'pantalla'); la sesión queda guardada en el aparato (REST_PERSISTENTE).
   El pedido va a la caja con pedido_local(): nace pendiente y la base calcula precios y total (§4.5). Todo texto de la base va con esc(). */
(() => {
  const { $, $$, esc, plata, aviso } = window.RUI, R = window.RESTDATA;
  const INACTIVO_MS = 90000, LISTO_MS = 15000;
  const carrito = new Map();                 // clave → cantidad
  let productos = [], extras = [], todos = [], cat = null, timerInactivo = null, timerListo = null, enviando = false;

  /* foto de cada producto: solo la suya (el recorte de la vitrina). La foto de la categoría va en su pestaña, no en cada burger: no se muestra una burger por otra */
  const fotoDe = p => { const v = (R.vitrina || []).find(x => x.id === p.clave); return v ? { src: v.corte, alt: v.alt } : null; };
  const categorias = () => (R.categorias || []).filter(c => productos.some(p => c.ids.includes(p.clave)));

  /* ---------- pasos ---------- */
  function ir(paso) {
    ['reposo', 'menu', 'pedido', 'listo'].forEach(k => { $('#kp-' + k).hidden = k !== paso; });
    clearTimeout(timerListo);
    if (paso === 'reposo') reiniciar();
    if (paso === 'menu') pintarMenu();
    if (paso === 'pedido') pintarPedido();
    if (paso === 'listo') timerListo = setTimeout(() => ir('reposo'), LISTO_MS);
    window.scrollTo(0, 0);
  }
  function reiniciar() { carrito.clear(); const f = $('#kp-form'); f.reset(); $('#kp-error').hidden = true; cat = null; pintarPie(); }
  function tocar() { clearTimeout(timerInactivo); timerInactivo = setTimeout(() => { if ($('#kp-reposo').hidden) ir('reposo'); }, INACTIVO_MS); }
  ['pointerdown', 'keydown', 'input'].forEach(ev => document.addEventListener(ev, tocar, { passive: true }));
  $$('[data-ir]').forEach(b => b.onclick = () => ir(b.dataset.ir));
  $('#kp-empezar').onclick = async () => { await cargar(); ir('menu'); };

  /* ---------- carta en vivo (precios y agotados vienen de la base) ---------- */
  async function cargar() {
    try { todos = (await window.REST.rpc('carta')).productos; }
    catch (e) { todos = (R.productos || []).map(p => ({ ...p, agotado: false })); aviso('Sin conexión: la carta puede no estar al día.', true); }
    productos = todos.filter(p => p.categoria !== 'extras'); extras = todos.filter(p => p.categoria === 'extras' && !p.agotado);
  }

  function pintarMenu() {
    const cs = categorias(); if (!cat || !cs.some(c => c.id === cat)) cat = cs.length ? cs[0].id : null;
    $('#kp-cats').innerHTML = cs.map(c => { const v = c.corte ? { src: c.corte } : (R.vitrina || []).find(x => c.ids.includes(x.id)), img = v ? (v.src || v.corte) : null;
      return `<button type="button" class="kp-cat" data-cat="${esc(c.id)}" aria-pressed="${c.id === cat}">${img ? `<img src="${esc(img)}" alt="" width="64" height="48">` : ''}<span><b>${esc(c.nombre)}</b>${c.sub ? `<small>${esc(c.sub)}</small>` : ''}</span></button>`; }).join('');
    $$('.kp-cat').forEach(b => b.onclick = () => { cat = b.dataset.cat; pintarMenu(); });
    const c = cs.find(x => x.id === cat), ps = c ? c.ids.map(id => productos.find(p => p.clave === id)).filter(Boolean) : productos;
    $('#kp-grilla').innerHTML = ps.map(p => { const f = fotoDe(p), n = carrito.get(p.clave) || 0;
      return `<article class="kp-prod${p.agotado ? ' agotado' : ''}${f ? '' : ' sin-foto'}">
        ${f ? `<div class="kp-prod-foto"><img src="${esc(f.src)}" alt="${esc(f.alt)}" loading="lazy"></div>` : ''}${p.agotado ? '<span class="kp-agotado">Agotada hoy</span>' : ''}
        <h2>${esc(p.nombre)}</h2>${p.ingredientes ? `<p>${esc(p.ingredientes)}</p>` : ''}
        <div class="kp-prod-pie"><b>${plata(p.precio_cent)}</b>
          ${p.agotado ? '' : n ? `<span class="kp-cant"><button type="button" data-menos="${esc(p.clave)}" aria-label="Quitar uno de ${esc(p.nombre)}">−</button><b>${n}</b><button type="button" data-mas="${esc(p.clave)}" aria-label="Sumar uno de ${esc(p.nombre)}">+</button></span>`
            : `<button type="button" class="rest-btn" data-mas="${esc(p.clave)}">Agregar</button>`}</div></article>`; }).join('');
    $$('[data-mas]', $('#kp-grilla')).forEach(b => b.onclick = () => {
      const p = productos.find(x => x.clave === b.dataset.mas);
      if (p && p.cuenta_burger && extras.length) abrirExtras(p); else { sumar(b.dataset.mas, 1); pintarMenu(); } });
    $$('[data-menos]', $('#kp-grilla')).forEach(b => b.onclick = () => { sumar(b.dataset.menos, -1); pintarMenu(); });
    pintarPie();
  }
  /* Extras (carne, queso, tocino…): al agregar una burger se ofrecen en una ventana; van como productos aparte y la base calcula su precio (§4.5) */
  function abrirExtras(p) {
    let d = $('#kp-extras');
    if (!d) { d = document.createElement('dialog'); d.id = 'kp-extras'; d.className = 'kp-extras'; document.body.appendChild(d); }
    const sel = new Set(), total = () => p.precio_cent + [...sel].reduce((s, c) => s + extras.find(x => x.clave === c).precio_cent, 0);
    d.innerHTML = `<h2>${esc(p.nombre)}</h2><p>¿Le subimos el nivel? <small>Extras opcionales</small></p>
      <div class="kp-extras-fila">${extras.map(x => `<label><input type="checkbox" value="${esc(x.clave)}"><span>${esc(x.nombre)}<b>+${plata(x.precio_cent)}</b></span></label>`).join('')}</div>
      <div class="kp-extras-acc"><button type="button" class="rest-btn sec kp-grande" data-x="no">Cancelar</button><button type="button" class="rest-btn kp-grande" data-x="si">Agregar · <span id="kp-x-tot">${plata(p.precio_cent)}</span></button></div>`;
    $$('input', d).forEach(c => c.onchange = () => { c.checked ? sel.add(c.value) : sel.delete(c.value); $('#kp-x-tot', d).textContent = plata(total()); });
    $('[data-x=no]', d).onclick = () => d.close();
    $('[data-x=si]', d).onclick = () => { sumar(p.clave, 1); sel.forEach(c => sumar(c, 1)); d.close(); pintarMenu(); };
    d.showModal();
  }
  function sumar(clave, d) { const n = Math.max(0, Math.min(20, (carrito.get(clave) || 0) + d)); n ? carrito.set(clave, n) : carrito.delete(clave); }
  const lineas = () => [...carrito].map(([c, n]) => ({ p: todos.find(x => x.clave === c), n })).filter(x => x.p);
  const subtotal = () => lineas().reduce((s, x) => s + x.p.precio_cent * x.n, 0);
  function pintarPie() {
    const n = lineas().reduce((s, x) => s + x.n, 0); $('#kp-pie').hidden = !n;
    $('#kp-n').textContent = n; $('#kp-n-txt').textContent = n === 1 ? 'producto' : 'productos'; $('#kp-sub').textContent = plata(subtotal());
  }

  function pintarPedido() {
    const ls = lineas();
    if (!ls.length) { ir('menu'); return; }
    $('#kp-lineas').innerHTML = ls.map(({ p, n }) => `<li><span>${esc(p.nombre)}</span><span class="kp-cant"><button type="button" data-menos="${esc(p.clave)}" aria-label="Quitar uno de ${esc(p.nombre)}">−</button><b>${n}</b><button type="button" data-mas="${esc(p.clave)}" aria-label="Sumar uno de ${esc(p.nombre)}">+</button></span><b>${plata(p.precio_cent * n)}</b></li>`).join('');
    $$('[data-mas]', $('#kp-lineas')).forEach(b => b.onclick = () => { sumar(b.dataset.mas, 1); pintarPedido(); });
    $$('[data-menos]', $('#kp-lineas')).forEach(b => b.onclick = () => { sumar(b.dataset.menos, -1); pintarPedido(); });
    $('#kp-total').textContent = plata(subtotal());
    /* sugerencia (menu.sugerir, ej. bebidas): fila de un toque antes del nombre */
    const sc = R.sugerir && (R.categorias || []).find(c => c.id === R.sugerir.categoria), caja = $('#kp-sugerir');
    const ps = sc ? sc.ids.map(id => productos.find(p => p.clave === id)).filter(p => p && !p.agotado) : [];
    caja.hidden = !ps.length;
    caja.innerHTML = ps.length ? `<p>${esc(R.sugerir.titulo || '¿Le sumas algo más?')}</p><div class="kp-sug-fila">${ps.map(p => { const n = carrito.get(p.clave) || 0;
      return `<button type="button" class="kp-sug${n ? ' on' : ''}" data-sug="${esc(p.clave)}"><span>${esc(p.nombre)}</span><b>+${plata(p.precio_cent)}</b>${n ? `<i>${n}</i>` : ''}</button>`; }).join('')}</div>` : '';
    $$('[data-sug]', caja).forEach(b => b.onclick = () => { sumar(b.dataset.sug, 1); pintarPedido(); });
  }

  $('#kp-form').onsubmit = async e => {
    e.preventDefault(); if (enviando) return;
    const f = e.target, err = $('#kp-error'), btn = $('#kp-enviar'); err.hidden = true;
    if (!f.modo.value) { err.textContent = 'Elige comer aquí o para llevar.'; err.hidden = false; return; }
    enviando = true; btn.disabled = true; btn.textContent = 'Enviando…';
    try {
      const r = await window.REST.rpc('pedido_local', { p_nombre: f.nombre.value.trim(), p_modo: f.modo.value, p_nota: [...f.querySelectorAll('input[name=sin]:checked')].map(x => x.value).join(', ') || null,   // «Sin cebolla, Sin tomate» llega a caja como nota para cocina
        p_lineas: [...carrito].map(([producto, cantidad]) => ({ producto, cantidad })) });
      $('#kp-numero').textContent = r.numero; $('#kp-pagar').textContent = plata(r.total_cent);
      carrito.clear(); ir('listo');
    } catch (er) {
      err.textContent = er.message; err.hidden = false;
      if (/agot|stock|disponible/i.test(er.message)) { await cargar(); }
    } finally { enviando = false; btn.disabled = false; btn.textContent = 'Enviar pedido'; }
  };

  /* ---------- salir: mantener presionado el logo del reposo 5 s (solo el personal lo sabe) ---------- */
  let tPres = null;
  $('#kp-logo').addEventListener('pointerdown', e => { e.stopPropagation(); tPres = setTimeout(() => { if (confirm('¿Cerrar la sesión de esta pantalla? Para volver a usarla hay que entrar con la cuenta de la pantalla.')) { window.REST.salir(); location.reload(); } }, 5000); });
  ['pointerup', 'pointerleave', 'pointercancel'].forEach(ev => $('#kp-logo').addEventListener(ev, () => clearTimeout(tPres)));

  /* ---------- arranque ---------- */
  function alEntrar() {
    $('#kp-entrada-caja').hidden = true; $('#kp').hidden = false;
    const v = (R.vitrina || [])[0]; if (v) $('#kp-foto').innerHTML = `<img src="${esc(v.corte)}" alt="" width="520" height="400">`;
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js', { scope: './pantalla' }).catch(() => {});
    cargar(); ir('reposo');
  }
  window.RUI.sesion({ raiz: $('#kp-entrada'), roles: ['pantalla', 'admin'], titulo: 'Activar la pantalla del local', texto: 'Entra una sola vez con la cuenta de la pantalla. La tablet queda lista para que los clientes pidan solos.', alEntrar });
})();

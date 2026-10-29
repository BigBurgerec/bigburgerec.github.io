/* Módulo de restaurante · pantalla de ventas del personal: registrar ventas del local con un toque, confirmar pedidos de la web y anular errores.
   El total y el stock los calcula la base; aquí solo se arma la lista. Todo texto de la base va con esc(). */
(() => {
  const { $, $$, esc, plata, hhmm, hace, canalTxt, origenTxt, modoTxt, aviso } = window.RUI, R = window.RESTDATA;
  const ticket = new Map();          // clave → cantidad
  let productos = [], yo = null, clave = null, ocupado = false, timer = null;
  const nuevaClave = () => (crypto.randomUUID ? crypto.randomUUID() : 'k' + Date.now() + Math.random().toString(36).slice(2));
  const GRUPOS = [['Hamburguesas', p => p.cuenta_burger], ['Papas y bebidas', p => !p.cuenta_burger && p.categoria !== 'extras'], ['Extras', p => p.categoria === 'extras']];

  function estadoStock(p) { if (!p.controla_stock || p.quedan == null) return null; return p.quedan <= 0 ? 'agotado' : p.quedan <= R.stock_bajo ? 'bajo' : 'ok'; }
  function pintarBotones() {
    $('#rp-botones').innerHTML = GRUPOS.map(([tit, f]) => { const ps = productos.filter(f); return ps.length ? `<div class="rp-grupo"><h2>${tit}</h2><div class="rp-botones">${ps.map(p => {
      const e = estadoStock(p), c = ticket.get(p.clave) || 0, sin = e === 'agotado';
      return `<button type="button" class="rp-prod" data-c="${esc(p.clave)}" ${sin ? 'disabled' : ''}><span>${esc(p.nombre)}</span><span class="precio">${plata(p.precio_cent)}</span>
        ${e ? `<span class="q" style="color:${e === 'ok' ? '#7fe07f' : e === 'bajo' ? 'var(--d-aviso)' : '#ff9a9a'}">${e === 'ok' ? '●' : e === 'bajo' ? '▲' : '■'} ${sin ? 'Agotado' : `Quedan ${p.quedan}`}</span>` : ''}${c ? `<span class="cant">${c}</span>` : ''}</button>`; }).join('')}</div></div>` : ''; }).join('');
    $$('.rp-prod').forEach(b => b.onclick = () => { ticket.set(b.dataset.c, (ticket.get(b.dataset.c) || 0) + 1); pintarTicket(); });
  }
  function pintarTicket() {
    const ls = [...ticket].map(([c, n]) => ({ p: productos.find(x => x.clave === c), n })).filter(x => x.p);
    $('#rp-lineas').innerHTML = ls.map(({ p, n }) => `<li><span>${esc(p.nombre)}</span><span class="mas"><button type="button" data-m="${esc(p.clave)}" aria-label="Quitar uno de ${esc(p.nombre)}">−</button><b>${n}</b><button type="button" data-p="${esc(p.clave)}" aria-label="Sumar uno de ${esc(p.nombre)}">+</button></span><span>${plata(p.precio_cent * n)}</span></li>`).join('');
    $('#rp-vacio').hidden = !!ls.length; $('#rp-total').textContent = plata(ls.reduce((s, x) => s + x.p.precio_cent * x.n, 0));
    $('#rp-registrar').disabled = !ls.length || ocupado;
    $$('[data-p]').forEach(b => b.onclick = () => { ticket.set(b.dataset.p, ticket.get(b.dataset.p) + 1); pintarTicket(); });
    $$('[data-m]').forEach(b => b.onclick = () => { const n = ticket.get(b.dataset.m) - 1; n ? ticket.set(b.dataset.m, n) : ticket.delete(b.dataset.m); pintarTicket(); });
    pintarBotones();
  }
  async function stock() { try { productos = await window.REST.rpc('stock_hoy'); pintarBotones(); } catch (e) { aviso(e.message, true); } }

  $('#rp-registrar').onclick = async () => {
    if (ocupado || !ticket.size) return; ocupado = true; clave = clave || nuevaClave(); $('#rp-registrar').disabled = true;
    try {
      const r = await window.REST.rpc('venta_registrar', { p_lineas: [...ticket].map(([producto, cantidad]) => ({ producto, cantidad })), p_clave: clave });
      aviso(`Venta #${r.numero} registrada · ${plata(r.total_cent)}`); ticket.clear(); clave = null; await Promise.all([stock(), ventas()]);
    } catch (e) { aviso(e.message, true); if (/stock|disponible/i.test(e.message)) { clave = null; stock(); } }
    finally { ocupado = false; pintarTicket(); }
  };
  $('#rp-limpiar').onclick = () => { ticket.clear(); clave = null; pintarTicket(); };

  /* ---------- pedidos que esperan a la caja: de la web (también llegan por WhatsApp) y de la pantalla del local (se pagan en caja) ---------- */
  const mapsOk = u => /^https:\/\/(www\.google\.com\/maps|maps\.google\.com|maps\.app\.goo\.gl|goo\.gl\/maps)([/?#]|$)/.test(u || '');
  /* Pedidos de la pantalla del local que esperan: naranja desde los N min y rojo desde los M (restaurante.pantalla.alerta_min, por defecto [4, 8]) */
  const ALERTA = (R.pantalla_alerta && R.pantalla_alerta.length === 2) ? R.pantalla_alerta : [4, 8];
  const espera = p => Math.floor((Date.now() - new Date(p.creado)) / 60000);
  const demora = p => { if (p.origen !== 'pantalla' || p.vencido) return ''; const m = espera(p); return m >= ALERTA[1] ? ' demora-roja' : m >= ALERTA[0] ? ' demora-naranja' : ''; };
  const etiquetas = p => { const o = p.origen || 'web';
    return `<span class="rp-tag origen-${esc(o)}">${esc(origenTxt(o))}</span> <span class="rp-tag ${o === 'pantalla' ? 'local' : esc(p.canal)}">${esc(o === 'pantalla' ? modoTxt(p.modo) : canalTxt(p.canal))}</span>`
      + (o === 'pantalla' ? ' <span class="rp-tag caja">Pagar en caja</span>' : '') + (p.vencido ? ' <span class="rp-tag vencido">Venció</span>' : ''); };

  /* Aviso con sonido cuando llega un pedido nuevo: dos notas para la web, tres toques cortos para la pantalla. Se apaga con el botón «Sonido». */
  const vistos = new Set(); let primeraCarga = true, audio = null;
  const sonidoOn = () => { try { return localStorage.getItem('rest_sonido') !== 'no'; } catch (e) { return true; } };
  function pintarSonido() { const b = $('#rp-sonido'); if (b) { b.setAttribute('aria-pressed', sonidoOn()); b.textContent = sonidoOn() ? 'Sonido: sí' : 'Sonido: no'; } }
  function sonar(origen) {
    if (!sonidoOn()) return;
    try {
      audio = audio || new (window.AudioContext || window.webkitAudioContext)(); if (audio.state === 'suspended') audio.resume();
      const notas = origen === 'pantalla' ? [[880, 0], [880, .18], [880, .36]] : [[660, 0], [990, .22]];
      notas.forEach(([f, t]) => { const o = audio.createOscillator(), g = audio.createGain(), t0 = audio.currentTime + t;
        o.frequency.value = f; o.type = 'sine'; g.gain.setValueAtTime(.0001, t0); g.gain.exponentialRampToValueAtTime(.35, t0 + .02); g.gain.exponentialRampToValueAtTime(.0001, t0 + .16);
        o.connect(g).connect(audio.destination); o.start(t0); o.stop(t0 + .18); });
    } catch (e) { /* sin audio */ }
  }
  document.addEventListener('pointerdown', () => { if (audio && audio.state === 'suspended') audio.resume(); }, { passive: true });

  async function pedidos() {
    try {
      const ps = await window.REST.rpc('pedidos_pendientes'), n = $('#rp-n'), nuevos = ps.filter(p => !vistos.has(p.id) && !p.vencido);
      ps.forEach(p => vistos.add(p.id));
      if (!primeraCarga && nuevos.length) { sonar(nuevos.some(p => p.origen === 'pantalla') ? 'pantalla' : 'web'); aviso(`Pedido nuevo #${nuevos[nuevos.length - 1].numero} · ${origenTxt(nuevos[nuevos.length - 1].origen || 'web')}`); }
      primeraCarga = false;
      const vivos = ps.filter(p => !p.vencido).length; n.hidden = !vivos; n.textContent = vivos;
      $('#rp-pedidos').innerHTML = ps.length ? ps.map(p => `<article class="rest-tarjeta rp-item${p.origen === 'pantalla' ? ' de-pantalla' : ''}${demora(p)}"><header><h3>#${p.numero} · ${esc(p.cliente)}${demora(p) ? ` <span class="rp-espera">Esperando ${espera(p)} min</span>` : ''}</h3><span>${etiquetas(p)}</span></header>
        <p><b>${p.lineas.map(l => `${l.cantidad}× ${esc(l.nombre)}`).join(' · ')}</b></p>
        <p>Total <b>${plata(p.total_cent)}</b>${p.envio_cent ? ` (incluye envío ${plata(p.envio_cent)})` : ''} · llegó ${hace(p.creado)}${p.programado ? ` · para las ${hhmm(p.programado)}` : ''}</p>
        ${p.canal === 'domicilio' ? `<p>${esc(p.sector)} · ${esc(p.direccion)} ${mapsOk(p.maps_url) ? `· <a class="enlace" href="${esc(p.maps_url)}" target="_blank" rel="noopener">Abrir en Google Maps</a>` : ''}</p>` : ''}
        ${p.nota ? `<p class="rp-nota">Nota para cocina: ${esc(p.nota)}</p>` : ''}
        ${p.telefono ? `<p>Celular <a class="enlace" href="https://wa.me/${esc(p.telefono)}" target="_blank" rel="noopener">${esc(p.telefono)}</a></p>` : ''}
        <div class="acc">${p.vencido ? '' : `<button type="button" class="rest-btn" data-acc="confirmar" data-id="${p.id}">Confirmar</button>`}<button type="button" class="rest-btn peligro" data-acc="rechazar" data-id="${p.id}">Rechazar</button></div></article>`).join('')
        : '<p class="rest-sub">No hay pedidos esperando. Cuando llegue uno de la web o de la pantalla del local, aparece aquí y suena un aviso.</p>';
      $$('[data-acc]', $('#rp-pedidos')).forEach(b => b.onclick = async () => { b.disabled = true;
        try { await window.REST.rpc('pedido_resolver', { p_id: +b.dataset.id, p_accion: b.dataset.acc }); aviso(b.dataset.acc === 'confirmar' ? 'Pedido confirmado: entra a cocina.' : 'Pedido rechazado.'); await Promise.all([pedidos(), stock(), ventas()]); }
        catch (e) { aviso(e.message, true); b.disabled = false; pedidos(); stock(); } });
    } catch (e) { /* se reintenta en el siguiente ciclo */ }
  }

  /* ---------- mis ventas ---------- */
  async function ventas() {
    try {
      const vs = await window.REST.rpc('ventas_hoy');
      $('#rp-ventas').innerHTML = vs.length ? vs.map(v => `<article class="rest-tarjeta rp-item"><header><h3>#${v.numero} · ${plata(v.total_cent)}</h3><span>${v.origen && v.origen !== 'staff' ? `<span class="rp-tag origen-${esc(v.origen)}">${esc(origenTxt(v.origen))}</span> ` : ''}<span class="rp-tag ${v.estado === 'anulada' ? 'anulada' : v.canal}">${v.estado === 'anulada' ? 'Anulada' : v.origen === 'pantalla' ? esc(modoTxt(v.modo)) : canalTxt(v.canal)}</span></span></header>
        <p>${v.lineas.map(l => `${l.cantidad}× ${esc(l.nombre)}`).join(' · ')}</p><p>${v.cliente ? esc(v.cliente) + ' · ' : ''}${hhmm(v.creado)}${yo.rol === 'admin' && v.quien ? ' · ' + esc(v.quien) : ''}</p>
        ${v.puede_anular ? `<div class="acc"><button type="button" class="rest-btn peligro chico" data-anular="${v.id}">Anular</button></div>` : ''}</article>`).join('')
        : '<p class="rest-sub">Todavía no hay ventas hoy.</p>';
      $$('[data-anular]').forEach(b => b.onclick = () => anular(+b.dataset.anular));
    } catch (e) { /* se reintenta */ }
  }
  function anular(id) {
    const d = $('#rp-dialogo'), m = $('#rp-motivo'); m.value = ''; d.showModal();
    d.onclose = async () => { if (d.returnValue !== 'si' || m.value.trim().length < 3) return;
      try { await window.REST.rpc('venta_anular', { p_id: id, p_motivo: m.value.trim() }); aviso('Venta anulada: el stock volvió.'); await Promise.all([ventas(), stock()]); } catch (e) { aviso(e.message, true); } };
  }


  /* ---------- premios del juego (módulo adicional): el código se canjea contra una venta real de hoy ---------- */
  const fp = $('#rp-premio-form');
  if (fp) {
    const ok = $('#rp-premio-ok'), info = $('#rp-premio-info'), sel = $('#rp-premio-venta'), cod = $('#rp-codigo');
    async function ventasParaCanje() {
      try {
        const min = (await window.REST.rpc('juego_estado')).compra_min_cent || 0, vs = (await window.REST.rpc('ventas_hoy')).filter(v => v.estado === 'confirmada' && v.total_cent >= min);
        sel.innerHTML = vs.length ? vs.map(v => `<option value="${v.numero}">#${v.numero} · ${plata(v.total_cent)} · ${hhmm(v.creado)}</option>`).join('') : `<option value="">No hay ventas tuyas de hoy desde ${plata(min)}</option>`;
      } catch (e) { /* se reintenta */ }
    }
    cod.oninput = async () => {
      cod.value = cod.value.toUpperCase().replace(/[^A-Z0-9]/g, ''); info.textContent = ''; ok.disabled = true;
      if (cod.value.length !== 6) return;
      try { const r = await window.REST.rpc('juego_codigo', { p_codigo: cod.value }); await ventasParaCanje();
        info.innerHTML = `<p><b>${esc(r.premio)}</b> para ${esc(r.nombre)} (celular terminado en ${esc(r.telefono_fin)}) · ${r.estado === 'pendiente' ? 'listo para canjear' : esc(r.estado)}</p>`; ok.disabled = r.estado !== 'pendiente' || !sel.value; }
      catch (e) { info.innerHTML = `<p class="rest-error">${esc(e.message)}</p>`; }
    };
    fp.onsubmit = async e => { e.preventDefault(); ok.disabled = true;
      try { const r = await window.REST.rpc('juego_canjear', { p_codigo: cod.value, p_numero_venta: parseInt(sel.value, 10) }); aviso(`Premio entregado: ${r.premio} para ${r.nombre} (venta #${r.venta}).`); cod.value = ''; info.textContent = ''; }
      catch (er) { aviso(er.message, true); ok.disabled = false; } };
    $('#t-premios').addEventListener('click', ventasParaCanje);
  }

  /* ---------- pestañas y arranque ---------- */
  function pestana(k) { ['vender', 'pedidos', 'ventas', 'premios'].filter(t => $('#t-' + t)).forEach(t => { $('#t-' + t).setAttribute('aria-selected', t === k); $('#p-' + t).hidden = t !== k; }); if (k === 'pedidos') pedidos(); if (k === 'ventas') ventas(); history.replaceState(null, '', '#' + k); }
  ['vender', 'pedidos', 'ventas', 'premios'].filter(k => $('#t-' + k)).forEach(k => $('#t-' + k).onclick = () => pestana(k));
  $('#rp-salir').onclick = () => { window.REST.salir(); location.reload(); };
  const bs = $('#rp-sonido'); if (bs) { pintarSonido(); bs.onclick = () => { try { localStorage.setItem('rest_sonido', sonidoOn() ? 'no' : 'si'); } catch (e) { /* sin almacenamiento */ } pintarSonido(); if (sonidoOn()) sonar('web'); }; }
  function alEntrar(u) {
    yo = u; $('#rp-app').hidden = false; $('#rp-quien').textContent = `${u.nombre} · ${u.rol === 'admin' ? 'Dueño' : 'Ventas'}`; stock(); pedidos(); ventas(); pintarTicket();
    const h = location.hash.slice(1); if (['pedidos', 'ventas'].includes(h)) pestana(h);
    timer = setInterval(() => { if (!document.hidden) { stock(); pedidos(); } }, 6000);
    setInterval(() => { if (document.hidden) pedidos(); }, 20000);   // con la pestaña en segundo plano igual avisa (más espaciado)
    window.addEventListener('storage', () => { stock(); pedidos(); ventas(); });
  }
  window.RUI.sesion({ raiz: $('#rp-entrada'), roles: ['vendedor', 'admin'], titulo: R.personal_txt.entrada_titulo, texto: R.personal_txt.entrada_texto, alEntrar });
})();

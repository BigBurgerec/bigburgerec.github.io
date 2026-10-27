/* Módulo de restaurante · vitrina de burgers (la página que ve el cliente). Datos: RESTDATA.vitrina + carta() de la base (lo que queda hoy). */
(() => {
  const { $, $$, esc, plata } = window.RUI, R = window.RESTDATA, V = R.vitrina, T = R.burgers_txt;
  const slides = $('#rb-escena'), glows = $('#rb-glows'), filas = $('#rb-filas');
  let i = 0, carta = null;
  const fijo = filas.hasAttribute('data-fijo');   // complemento «escaparate»: una palabra fija (la marca) en lugar de las filas con el nombre de cada burger
  const noMov = matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* la primera burger ya viene en el HTML (es lo que más tarda en pintarse): se conserva y solo se agregan las demás */
  const estatica = slides.querySelector('.rb-slide');
  if (estatica) estatica.setAttribute('aria-label', `1 de ${V.length}`);
  slides.insertAdjacentHTML('beforeend', V.map((b, n) => estatica && n === 0 ? '' : `<div class="rb-slide" data-n="${n}" role="group" aria-roledescription="diapositiva" aria-label="${n + 1} de ${V.length}"><img src="${esc(b.corte)}" alt="${esc(b.alt)}" ${n ? 'loading="lazy"' : ''}></div>`).join(''));
  glows.innerHTML = V.map(b => `<div class="rb-glow" style="--g:${esc(b.glow)}"></div>`).join('');

  const quedan = id => carta && (carta.productos.find(p => p.clave === id) || {}).quedan;
  const agotada = id => carta && (carta.productos.find(p => p.clave === id) || {}).agotado;

  function filasTexto(nombre) {
    const t = (nombre.split('+')[0].trim() + ' ').repeat(9);
    filas.innerHTML = [0, 1, 2, 3].map(k => `<div class="rb-fila${k % 2 ? ' contorno' : ''}"><span>${esc(t)}</span></div>`).join('');
  }

  function pintar(n, primera) {
    i = (n + V.length) % V.length; const b = V[i];
    $$('.rb-slide', slides).forEach((s, k) => { s.classList.toggle('on', k === i); s.classList.toggle('antes', k < i); s.setAttribute('aria-hidden', k === i ? 'false' : 'true'); });
    $$('.rb-glow', glows).forEach((g, k) => g.classList.toggle('on', k === i));
    const cambiar = () => filasTexto(b.titulo || b.nombre);
    if (fijo) { /* la palabra no cambia */ } else if (primera || noMov) cambiar(); else { filas.classList.add('cambia'); setTimeout(() => { cambiar(); filas.classList.remove('cambia'); }, 260); }
    $('#rb-intro').textContent = b.intro; $('#rb-nombre').textContent = b.titulo || b.nombre;
    $('#rb-precio').textContent = b.precio_cent ? plata(b.precio_cent) : b.etiqueta; $('#rb-n').textContent = i + 1;
    detalle(b);
  }

  function detalle(b) {
    $('#rb-det-tit').innerHTML = `<span>${esc(T.lleva)}</span>${esc(b.nombre)}`;
    const ing = (b.ingredientes || '').split(/,\s*| y (?=[a-záéíóúñ])/i).map(x => x.trim()).filter(Boolean);
    $('#rb-fichas').innerHTML = ing.length ? ing.map(x => `<span class="rb-ficha">${esc(x[0].toUpperCase() + x.slice(1))}</span>`).join('') : `<span class="rb-ficha">${esc(T.sin_ingredientes)}</span>`;
    $('#rb-det-txt').textContent = b.intro;
    const q = b.id ? quedan(b.id) : null, ag = b.id ? agotada(b.id) : false;
    $('#rb-quedan').innerHTML = b.id && q != null ? `<span class="rb-quedan ${ag ? 'agotado' : q <= R.stock_bajo ? 'bajo' : ''}"><i></i>${ag ? esc(T.agotada) : esc(T.quedan.replace('{n}', q))}</span>` : '';
    /* «Pedir esta burger» abre el pedido con esa burger (si lleva extras, la hoja de extras); la de temporada se consulta por WhatsApp */
    const pedir = $('#rb-pedir'); pedir.textContent = T.pedir_esta; pedir.href = '#carta'; pedir.onclick = null; pedir.removeAttribute('target');
    if (b.id) pedir.onclick = e => { if (window.Pedido) { e.preventDefault(); window.Pedido.abrirProducto(b.id); } };
    else { pedir.textContent = T.consultar; pedir.href = `https://wa.me/${window.DEMO.waCliente}?text=${encodeURIComponent(b.wa_texto || '')}`; pedir.target = '_blank'; pedir.rel = 'noopener'; }
  }

  $('#rb-ant').onclick = () => pintar(i - 1); $('#rb-sig').onclick = () => pintar(i + 1);
  document.addEventListener('keydown', e => { if (e.key === 'ArrowLeft') pintar(i - 1); if (e.key === 'ArrowRight') pintar(i + 1); });
  let x0 = null; const h = $('.rb-hero');
  h.addEventListener('touchstart', e => { x0 = e.touches[0].clientX; }, { passive: true });
  h.addEventListener('touchend', e => { if (x0 == null) return; const dx = e.changedTouches[0].clientX - x0; if (Math.abs(dx) > 45) pintar(i + (dx < 0 ? 1 : -1)); x0 = null; });
  const dlg = $('#rb-menu'); $('#rb-abrir').onclick = () => dlg.showModal(); $$('a', dlg).forEach(a => a.addEventListener('click', () => dlg.close()));
  /* cabecera fija al bajar: un observador, sin leer el scroll (evita un reflow forzado al cargar) */
  const cab = $('.rb-cab'), centinela = $('#rb-centinela');
  if (cab && centinela && 'IntersectionObserver' in window) new IntersectionObserver(([e]) => cab.classList.toggle('fijo', !e.isIntersecting && e.boundingClientRect.top < 0)).observe(centinela);
  pintar(0, true);

  /* ---------- categorías en fila ---------- */
  const cats = R.categorias.map(c => { const v = V.find(b => b.id && c.ids.includes(b.id)); return { ...c, corte: (v && v.corte) || c.corte, alt: (v && v.alt) || c.alt }; });
  $('#rb-cats').innerHTML = cats.map(c => `<a class="rb-cat" href="#cat-${esc(c.id)}"><div class="foto">${c.corte ? `<img src="${esc(c.corte)}" alt="" loading="lazy">` : `<img class="marca-agua" src="${esc(R.logo)}" alt="" loading="lazy">`}</div>
    <h3>${esc(c.nombre)} <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 18L18 6M8 6h10v10"/></svg></h3><p>${esc(c.sub)}</p></a>`).join('');

  /* ---------- contador LED ---------- */
  const F = { 0: '01110100011001110101110011000101110', 1: '00100011000010000100001000010001110', 2: '01110100010000100010001000100011111', 3: '11111000100010000010000011000101110', 4: '00010001100101010010111110001000010',
              5: '11111100001111000001000011000101110', 6: '00110010001000011110100011000101110', 7: '11111000010001000100010000100001000', 8: '01110100011000101110100011000101110', 9: '01110100011000101111000010001001100' };
  const dig = d => `<span class="rb-dig" aria-hidden="true">${[...F[d]].map(b => `<i class="${b === '1' ? 'on' : ''}"></i>`).join('')}</span>`;
  async function contador() {
    if (!$('#rb-led')) return;   // restaurante.sin_contador: la sección no está en la página
    try {
      const c = await window.REST.rpc('contador'); if (!c || !c.visible) return;
      const n = String(c.hamburguesas).padStart(7, '0').replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
      $('#rb-led-tit').textContent = T.led_titulo.replace('{anio}', c.anio);
      const box = $('#rb-led-cifras'); box.setAttribute('aria-label', `${c.hamburguesas} ${T.led_titulo.replace('{anio}', c.anio)}`);
      box.innerHTML = [...n].map(ch => ch === ' ' ? '<span class="sep"></span>' : dig(ch)).join('');
      $('#rb-led-ej').hidden = !c.ejemplo; $('#rb-led').hidden = false;
    } catch (e) { /* sin contador: la sección queda oculta */ }
  }

  /* ---------- lo que queda hoy (vive en la base) ---------- */
  window.REST.rpc('carta').then(c => { carta = c; detalle(V[i]); }).catch(() => {});
  contador();
})();

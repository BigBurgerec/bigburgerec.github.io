/* fx.js compartido · aparición en cascada al hacer scroll + contadores de cifras reales.
   Solo transform y opacity (Web Animations). El ritmo lo fija el perfil con variables CSS:
   --fx-rv-dur (ms), --fx-rv-step (ms), --fx-rv-ease, --fx-rv-dist, --fx-rv-scale (ver efectos/<perfil>.css).
   Sin JS, sin soporte o con movimiento reducido: todo se ve completo y quieto.
   Marcado: .fx-palabras separa un titular por palabras (efectos/texto.css); [data-reveal] anima un bloque; [data-stagger] anima a sus hijos en cascada; .fx-contador[data-contador] cuenta hasta el número. */
(() => {
  if (!('IntersectionObserver' in window) || !Element.prototype.animate || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const cs = getComputedStyle(document.documentElement);
  const v = (n, d) => cs.getPropertyValue(n).trim() || d;
  const dur = parseFloat(v('--fx-rv-dur', '600')), paso = parseFloat(v('--fx-rv-step', '90')), ease = v('--fx-rv-ease', 'ease-out');
  const dist = v('--fx-rv-dist', '24px'), esc = v('--fx-rv-scale', '1');
  const desde = { opacity: 0, transform: `translateY(${dist}) scale(${esc})` };
  const io = new IntersectionObserver(es => es.forEach(e => {
    if (!e.isIntersecting) return;
    const a = e.target.__rv; a.play(); a.onfinish = () => a.cancel(); io.unobserve(e.target);
  }), { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
  const preparar = (el, i) => {
    el.__rv = el.animate([desde, { opacity: 1, transform: 'none' }],
      { duration: dur, delay: Math.min(i, 6) * paso, easing: ease, fill: 'both' });
    el.__rv.pause(); io.observe(el);
  };
  const contar = el => {
    const fin = parseFloat(el.dataset.contador); if (!isFinite(fin)) return;
    const txt = el.textContent, fmt = n => Math.round(n).toLocaleString('es-EC');
    el.textContent = fmt(0);
    const co = new IntersectionObserver(es => es.forEach(e => {
      if (!e.isIntersecting) return; co.disconnect();
      const t0 = performance.now(), d = 1200;
      const paso = t => { const p = Math.min(1, (t - t0) / d); el.textContent = fmt(fin * (1 - Math.pow(1 - p, 3))); p < 1 ? requestAnimationFrame(paso) : (el.textContent = txt); };
      requestAnimationFrame(paso);
    }), { threshold: 0.4 });
    co.observe(el);
  };
  const vigilar = raiz => {
    raiz.querySelectorAll('[data-reveal]:not([data-rv])').forEach(el => { el.dataset.rv = 1; preparar(el, 0); });
    raiz.querySelectorAll('[data-stagger]:not([data-rv])').forEach(p => { p.dataset.rv = 1; [...p.children].forEach(preparar); });
    raiz.querySelectorAll('.fx-palabras:not([data-rv])').forEach(palabras);
    raiz.querySelectorAll('.fx-contador[data-contador]:not([data-rv])').forEach(el => { el.dataset.rv = 1; contar(el); });
  };
  /* Titulares por palabras (efectos/texto.css): se separan solo aquí, con JS y sin movimiento reducido. */
  const palabras = el => {
    if (el.dataset.rv) return; el.dataset.rv = 1;
    const txt = el.textContent.trim(); el.setAttribute('aria-label', txt);
    el.textContent = '';
    txt.split(/\s+/).forEach((w, i) => { const a = document.createElement('span'), b = document.createElement('span');
      a.className = 'fx-pal'; a.setAttribute('aria-hidden', 'true'); b.style.setProperty('--i', i); b.textContent = w; a.append(b); el.append(a, ' '); });
    const po = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { el.classList.add('fx-on'); po.disconnect(); } }), { threshold: 0.3 });
    po.observe(el);
  };
  vigilar(document);
  window.fxVigilar = vigilar;
  /* Al imprimir o guardar en PDF, todo bloque aún sin aparecer se muestra completo (sin esto saldría en blanco). */
  addEventListener('beforeprint', () => document.querySelectorAll('[data-rv], [data-stagger] > *').forEach(el => el.__rv && el.__rv.finish()));
})();

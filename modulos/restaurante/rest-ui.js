/* Módulo de restaurante · ayudas de pantalla. Todo texto que viene de la base o del cliente se inserta con esc() o textContent. */
(() => {
  const TZ = 'America/Guayaquil';
  const esc = t => String(t ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const plata = c => '$' + ((c || 0) / 100).toFixed(2);
  const num = n => Number(n || 0).toLocaleString('es-EC');
  const hhmm = iso => new Date(iso).toLocaleTimeString('es-EC', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: TZ });
  const fechaLarga = d => new Date(d + 'T12:00:00-05:00').toLocaleDateString('es-EC', { weekday: 'long', day: 'numeric', month: 'long', timeZone: TZ });
  const diaCorto = d => new Date(d + 'T12:00:00-05:00').toLocaleDateString('es-EC', { weekday: 'short', timeZone: TZ }).replace('.', '');
  const canalTxt = c => ({ local: 'En el local', llevar: 'Para llevar', domicilio: 'A domicilio' }[c] || c);
  const origenTxt = o => ({ web: 'Web', pantalla: 'Pantalla del local', staff: 'Caja' }[o] || o);
  const modoTxt = m => ({ aqui: 'Comer aquí', llevar: 'Para llevar' }[m] || '');
  const hace = iso => { const s = Math.max(0, Math.round((Date.now() - new Date(iso)) / 1000)); return s < 5 ? 'ahora' : s < 60 ? `hace ${s} s` : s < 3600 ? `hace ${Math.round(s / 60)} min` : `hace ${Math.round(s / 3600)} h`; };
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  /* Aviso corto en pantalla (lector de pantalla: role=status) */
  function aviso(texto, malo) {
    let c = $('#rest-avisos');
    if (!c) { c = document.createElement('div'); c.id = 'rest-avisos'; c.setAttribute('role', 'status'); c.setAttribute('aria-live', 'polite'); document.body.appendChild(c); }
    const a = document.createElement('div'); a.className = 'rest-aviso' + (malo ? ' malo' : ''); a.textContent = texto; c.appendChild(a);
    setTimeout(() => a.remove(), malo ? 6000 : 3200);
  }

  /* Tooltip único: el valor manda, la etiqueta acompaña. Solo textContent (los nombres vienen de la base). */
  let tip;
  function tooltip(el, fn) {
    const mostrar = e => {
      if (!tip) { tip = document.createElement('div'); tip.className = 'rest-tip'; tip.setAttribute('role', 'tooltip'); document.body.appendChild(tip); }
      const filas = fn(); tip.textContent = '';
      filas.forEach(([clave, valor, color]) => {
        const f = document.createElement('div'); f.className = 'rest-tip-f';
        if (color) { const k = document.createElement('i'); k.style.background = color; f.appendChild(k); }
        const v = document.createElement('b'); v.textContent = valor; const n = document.createElement('span'); n.textContent = clave;
        f.append(v, n); tip.appendChild(f);
      });
      tip.style.opacity = '1';
      const r = el.getBoundingClientRect(), x = e && e.clientX ? e.clientX : r.left + r.width / 2, y = r.top;
      const w = tip.offsetWidth; tip.style.left = Math.max(8, Math.min(innerWidth - w - 8, x - w / 2)) + 'px'; tip.style.top = Math.max(8, y - tip.offsetHeight - 10) + 'px';
    };
    const ocultar = () => { if (tip) tip.style.opacity = '0'; };
    el.addEventListener('pointermove', mostrar); el.addEventListener('pointerenter', mostrar); el.addEventListener('pointerleave', ocultar);
    el.addEventListener('focus', mostrar); el.addEventListener('blur', ocultar);
  }

  /* Pantalla de entrada del personal (dueño o empleado). Demo: se elige un usuario de ejemplo. Producción: correo y clave de Authentication.
     Después de entrar se pregunta a la base quién es (yo()) y se comprueba el rol. */
  async function sesion({ raiz, roles, titulo, texto, alEntrar }) {
    const R = window.RESTDATA, esDemo = window.REST.modo === 'demo';
    const mostrarEntrada = (aviso) => {
      raiz.hidden = false; raiz.innerHTML = `<div class="rest-entrar"><h2>${esc(titulo)}</h2><p>${esc(texto)}</p>${aviso ? `<p class="rest-error" role="alert">${esc(aviso)}</p>` : ''}
        ${esDemo ? `<p class="rest-chip-demo">Demo: elige con quién entrar</p><div class="rest-usuarios">${R.demo.usuarios.filter(u => roles.includes(u.rol)).map((u, i) => `<button type="button" class="rest-btn" data-u="${i}">${esc(u.nombre)}${(u.rol === 'admin' ? 'Dueño' : 'Empleado') === u.nombre ? '' : `<small>${u.rol === 'admin' ? 'Dueño' : 'Empleado'}</small>`}</button>`).join('')}</div>`
        : `<form class="rest-form" autocomplete="on"><label>Correo<input type="email" name="correo" autocomplete="username" required></label><label>Clave<input type="password" name="clave" autocomplete="current-password" required></label><button class="rest-btn" type="submit">Entrar</button></form>`}</div>`;
      if (esDemo) $$('[data-u]', raiz).forEach(b => b.onclick = () => { window.REST.entrarDemo(R.demo.usuarios.filter(u => roles.includes(u.rol))[+b.dataset.u]); verificar(); });
      else $('form', raiz).onsubmit = async e => { e.preventDefault(); const f = e.target, btn = $('button', f); btn.disabled = true;
        try { await window.REST.entrar(f.correo.value.trim(), f.clave.value); await verificar(); } catch (er) { mostrarEntrada(er.message); } };
    };
    const verificar = async () => {
      try {
        const yo = await window.REST.rpc('yo');
        if (!roles.includes(yo.rol)) { window.REST.salir(); mostrarEntrada(yo.rol === 'vendedor' ? 'Esta cuenta es de empleado: entra desde la pantalla de ventas.' : yo.rol === 'pantalla' ? 'Esta cuenta es de la pantalla del local: úsala solo en la tablet.' : 'Esta cuenta es del dueño: entra desde el dashboard.'); return; }
        raiz.hidden = true; raiz.innerHTML = ''; alEntrar(yo);
      } catch (er) { window.REST.salir(); mostrarEntrada(er.message); }
    };
    if (window.REST.haySesion()) verificar(); else mostrarEntrada();
  }

  window.RUI = { TZ, esc, plata, num, hhmm, fechaLarga, diaCorto, canalTxt, origenTxt, modoTxt, hace, $, $$, aviso, tooltip, sesion };
})();

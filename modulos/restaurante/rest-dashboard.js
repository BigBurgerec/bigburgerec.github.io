/* Módulo de restaurante · dashboard del dueño. Lee dashboard() cada pocos segundos (sin recargar la página) y pinta cada bloque.
   Gráficas en HTML (no SVG) para que el texto conserve su tamaño en el celular; cada gráfica tiene su vista de tabla. */
(() => {
  const { $, $$, esc, plata, num, hhmm, fechaLarga, diaCorto, canalTxt, hace, aviso, tooltip } = window.RUI, R = window.RESTDATA;
  const CAN = { local: 'var(--d-s1)', llevar: 'var(--d-s2)', domicilio: 'var(--d-s3)' };
  const ESTADO = { ok: ['●', 'Hay'], bajo: ['▲', 'Bajo'], agotado: ['■', 'Agotado'], sin_definir: ['○', 'Sin cargar'], libre: ['–', 'Sin control'] };
  const COLOR_ESTADO = { ok: 'var(--d-ok)', bajo: 'var(--d-aviso)', agotado: 'var(--d-crit)' };
  let D = null, timer = null, auto = null, vistos = new Set(), primera = true, editando = false;

  const raiz = $('#rd-app'), vivo = $('#rd-vivo');

  /* ---- bloques ---- */
  function pintarHeroe(d) {
    const r = d.resumen, sp = d.semana_pasada;
    $('#rd-hero').textContent = num(r.hamburguesas);
    $('#rd-fecha').textContent = fechaLarga(d.dia);
    const dif = r.hamburguesas - sp.hamburguesas_ahora, el = $('#rd-delta');
    if (sp.hamburguesas_ahora > 0 || r.hamburguesas > 0) {
      const pct = sp.hamburguesas_ahora ? Math.round(dif / sp.hamburguesas_ahora * 100) : null;
      el.hidden = false; el.className = 'rd-delta ' + (dif > 0 ? 'sube' : dif < 0 ? 'baja' : '');
      el.textContent = (dif > 0 ? '▲ ' : dif < 0 ? '▼ ' : '= ') + (dif === 0 ? 'Igual que' : `${Math.abs(dif)} ${dif > 0 ? 'más que' : 'menos que'}`) + ` el mismo día de la semana pasada a esta hora${pct != null && dif ? ` (${pct > 0 ? '+' : ''}${pct} %)` : ''}`;
    } else el.hidden = true;
    const rec = d.record, barra = $('#rd-rec-barra');
    if (rec) { barra.style.transform = `scaleX(${Math.min(1, r.hamburguesas / rec.hamburguesas)})`; $('#rd-rec-txt').textContent = `${num(r.hamburguesas)} de ${num(rec.hamburguesas)} del récord (${fechaLarga(rec.dia)})`; }
    else $('#rd-rec-txt').textContent = '';
  }
  function pintarKpis(d) {
    const r = d.resumen, pend = d.pendientes;
    const k = [
      ['Ingresos de hoy', plata(r.ingresos_cent), `Local ${plata(r.ingresos_local_cent)} · Web ${plata(r.ingresos_web_cent)}${r.envios_cent ? ` · + ${plata(r.envios_cent)} de envíos` : ''}`],
      ['Ventas (tickets)', num(r.ventas), `${num(r.unidades)} productos en total`],
      ['Ticket promedio', plata(r.ticket_cent), 'Por venta, sin envío'],
      [pend ? 'Pedidos por responder' : 'Pedidos de la web', pend ? num(pend) : '0', pend ? '<a href="personal.html#pedidos">Abrir y confirmar</a>' : 'Nada esperando']
    ];
    $('#rd-kpis').innerHTML = k.map(([a, b, c], n) => `<article class="rest-tarjeta rd-kpi${n === 3 && pend ? ' alerta' : ''}"><span class="rotulo">${a}</span><span class="valor">${b}</span><span class="pie">${c}</span></article>`).join('');
  }
  function pintarHoras(d) {
    const act = d.por_hora.filter(h => h.hamburguesas || h.anterior).map(h => h.h), ini = Math.min(11, ...act, d.hora), fin = Math.max(Math.min(23, d.hora + 1), 21, ...act);
    const horas = d.por_hora.filter(h => h.h >= ini && h.h <= fin), max = Math.max(1, ...horas.map(h => Math.max(h.hamburguesas, h.anterior))), tope = Math.max(4, Math.ceil(max / 4) * 4);
    const rejilla = [0, 0.5, 1].map(f => `<div style="bottom:${f * 100}%"></div><span style="bottom:${f * 100}%">${Math.round(tope * f)}</span>`).join('');
    const cols = horas.map(h => { const pct = h.hamburguesas / tope * 100, futura = h.h > d.hora, etiqueta = h.hamburguesas === max && h.hamburguesas > 0 || h.h === d.hora;
      return `<div class="rd-col${h.h === d.hora ? ' ahora' : ''}${futura ? ' futura' : ''}" tabindex="0" data-h="${h.h}" aria-label="${h.h}:00 ${h.hamburguesas} hamburguesas, semana pasada ${h.anterior}">
        ${etiqueta && !futura ? `<span class="v" style="bottom:${pct}%">${h.hamburguesas}</span>` : ''}<div class="barra" style="height:${pct}%"></div><span class="hh">${h.h}</span></div>`; }).join('');
    const pts = horas.map((h, k) => [(k + .5) / horas.length * 100, 100 - h.anterior / tope * 100]);
    const linea = `<svg class="rd-lineaS" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><polyline points="${pts.map(p => p.join(',')).join(' ')}"/></svg>`;
    const puntos = pts.map((p, k) => horas[k].anterior ? `<span class="rd-punto" style="left:calc(34px + (100% - 34px) * ${p[0] / 100});top:calc((100% - 26px) * ${p[1] / 100})"></span>` : '').join('');
    $('#rd-horas').innerHTML = `<div class="rejilla">${rejilla}</div><div class="rd-cols">${cols}</div>${linea}${puntos}`;
    $$('.rd-col', $('#rd-horas')).forEach(c => { const h = horas.find(x => x.h === +c.dataset.h); tooltip(c, () => [[`${h.h}:00 a ${h.h}:59`, `${h.hamburguesas} hamburguesas`, 'var(--fx-accent)'], ['Semana pasada', `${h.anterior}`, 'var(--d-mut)']]); });
    $('#rd-horas-tabla').innerHTML = `<table><thead><tr><th>Hora</th><th>Hoy</th><th>Semana pasada</th></tr></thead><tbody>${horas.map(h => `<tr><td>${h.h}:00</td><td>${h.hamburguesas}</td><td>${h.anterior}</td></tr>`).join('')}</tbody></table>`;
  }
  function pintarCanales(d) {
    const r = d.resumen, tot = r.hamburguesas || 1, cs = [['local', r.local], ['llevar', r.llevar], ['domicilio', r.domicilio]];
    $('#rd-canal').innerHTML = r.hamburguesas ? cs.filter(c => c[1]).map(([c, n]) => `<i style="flex:${n};background:${CAN[c]}" title="${canalTxt(c)}"></i>`).join('') : '<i style="flex:1;background:var(--d-line)"></i>';
    $('#rd-canal').setAttribute('aria-label', cs.map(([c, n]) => `${canalTxt(c)} ${n}`).join(', '));
    $('#rd-canal-lista').innerHTML = cs.map(([c, n]) => `<div><i style="background:${CAN[c]}"></i><span>${canalTxt(c)}</span><span><b>${num(n)}</b> <em>${Math.round(n / tot * 100)} %</em></span></div>`).join('');
  }
  function pintarProductos(d) {
    const burgers = d.productos.filter(p => p.cuenta_burger), otros = d.productos.filter(p => !p.cuenta_burger && p.vendidas > 0 && p.categoria !== 'extras'), maxV = Math.max(1, ...d.productos.map(p => p.vendidas));
    const fila = p => { const f = p.inicial ? Math.max(0, Math.min(1, p.quedan / p.inicial)) : 0, col = COLOR_ESTADO[p.estado] || 'var(--d-mut)', [ic, tx] = ESTADO[p.estado];
      return `<tr><td class="nom">${esc(p.nombre)}<small>${plata(p.precio_cent)}</small></td>
        <td><div class="rd-vend"><div class="pista"><i style="width:${p.vendidas / maxV * 100}%"></i></div><b>${p.vendidas}</b></div></td>
        <td><div class="rd-stock">${p.estado === 'libre' || p.estado === 'sin_definir' ? `<span><span class="rd-estado ${p.estado}">${ic} ${tx}</span></span>` :
          `<div class="pista"><i style="width:${f * 100}%;background:${col}"></i></div><span><b>${p.quedan} <small style="font-weight:400">de ${p.inicial}</small></b><span class="rd-estado ${p.estado}">${ic} ${tx}</span></span>`}</div></td></tr>`; };
    $('#rd-prod').innerHTML = burgers.map(fila).join('') + (otros.length ? `<tr><td colspan="3" style="padding-top:16px;color:var(--d-mut);font:700 .85rem var(--fx-font-txt);text-transform:uppercase;letter-spacing:.05em">Papas, bebidas y más</td></tr>` + otros.map(fila).join('') : '');
    const sin = burgers.filter(p => p.estado === 'sin_definir').length, baj = d.productos.filter(p => p.estado === 'bajo' || p.estado === 'agotado').length;
    $('#rd-stock-sub').textContent = sin ? `Faltan ${sin} burger${sin > 1 ? 's' : ''} por cargar: sin stock cargado se vende sin tope.` : baj ? `${baj} producto${baj > 1 ? 's' : ''} con poco o sin stock.` : 'Stock del día cargado por el dueño; baja solo con cada venta.';
    if (!editando) armarEditor(d);
  }
  function armarEditor(d) {
    const f = $('#rd-editor'); if (f.dataset.hecho === d.dia && !f.hidden) return;
    const ps = d.productos.filter(p => p.estado !== 'libre');
    f.innerHTML = ps.map(p => `<label class="rest-campo">${esc(p.nombre)}<input type="number" inputmode="numeric" min="${p.vendidas}" max="9999" step="1" name="${esc(p.clave)}" value="${p.inicial ?? ''}" placeholder="Hoy, en total"></label>`).join('') +
      `<div class="pie"><button type="submit" class="rest-btn">Guardar stock del día</button><button type="button" class="rest-btn sec" id="rd-editor-x">Cancelar</button><small>Pon cuántas hay para hoy en total (lo ya vendido cuenta dentro). Las ventas lo van bajando solas.</small></div>`;
    f.dataset.hecho = d.dia; $('#rd-editor-x').onclick = () => { f.hidden = true; editando = false; };
  }
  function pintarFeed(d) {
    const html = d.ultimas.map(v => { const nuevo = !primera && !vistos.has(v.id + v.estado); vistos.add(v.id + v.estado);
      return `<li class="${v.estado === 'anulada' ? 'anulada' : ''}${nuevo ? ' nuevo' : ''}"><span class="hora">${hhmm(v.creado)}</span><span><i class="rd-canalpunto" style="background:${CAN[v.canal]}"></i>${v.lineas.map(l => `${l.cantidad}× ${esc(l.nombre)}`).join(' · ')}</span><b>${plata(v.total_cent)}</b>
        <span class="det">#${v.numero} · ${canalTxt(v.canal)}${v.sector ? ' · ' + esc(v.sector) : ''}${v.quien ? ' · ' + esc(v.quien) : ''}${v.estado === 'anulada' ? ' · ANULADA' : ''}</span></li>`; }).join('');
    $('#rd-feed').innerHTML = html || '<li><span class="det" style="grid-column:1/-1">Aún no hay ventas hoy.</span></li>';
  }
  function pintarSemana(d) {
    const max = Math.max(1, ...d.semana.map(x => x.hamburguesas));
    $('#rd-semana').innerHTML = d.semana.map((x, n) => `<div class="c${n === 6 ? ' hoy' : ''}" tabindex="0" data-n="${n}" aria-label="${diaCorto(x.dia)} ${x.hamburguesas} hamburguesas"><span class="v">${n === 6 || x.hamburguesas === max ? x.hamburguesas : ''}</span><div class="b" style="height:${x.hamburguesas / max * 100}%"></div><span class="d">${n === 6 ? 'hoy' : diaCorto(x.dia)}</span></div>`).join('');
    $$('.c', $('#rd-semana')).forEach(c => { const x = d.semana[+c.dataset.n]; tooltip(c, () => [[fechaLarga(x.dia), `${x.hamburguesas} hamburguesas`, 'var(--fx-accent)'], ['Ingresos', plata(x.ingresos_cent)], ['Ventas', String(x.ventas)]]); });
    $('#rd-semana-tabla').innerHTML = `<table><thead><tr><th>Día</th><th>Hamburguesas</th><th>Ingresos</th></tr></thead><tbody>${d.semana.map(x => `<tr><td>${fechaLarga(x.dia)}</td><td>${x.hamburguesas}</td><td>${plata(x.ingresos_cent)}</td></tr>`).join('')}</tbody></table>`;
  }
  function pintarEquipo(d) {
    const max = Math.max(1, ...d.equipo.map(e => e.hamburguesas));
    $('#rd-equipo').innerHTML = d.equipo.length ? d.equipo.map(e => `<div class="p"><span>${esc(e.nombre)}</span><span><b>${e.hamburguesas}</b> hamburguesas · ${plata(e.ingresos_cent)}</span><div class="pista"><i style="width:${e.hamburguesas / max * 100}%"></i></div></div>`).join('') : '<p class="rest-sub">Aún nadie registró ventas hoy.</p>';
  }
  function pintarWeb(d) {
    const r = d.resumen;
    $('#rd-web').innerHTML = `<p class="rd-kpi"><span class="valor">${d.pendientes}</span></p><p class="rest-sub" style="margin:6px 0 12px">${d.pendientes ? 'pedidos esperan que el local los confirme.' : 'No hay pedidos esperando.'}</p>
      <p class="rest-sub">Ya confirmados hoy: <b style="color:var(--fx-bg)">${num(r.llevar + r.domicilio)}</b> hamburguesas (${num(r.llevar)} para llevar y ${num(r.domicilio)} a domicilio).</p><p style="margin-top:14px"><a class="rest-btn sec chico" href="personal.html#pedidos">Ir a los pedidos</a></p>`;
  }

  function pintar(d) {
    D = d; pintarHeroe(d); pintarKpis(d); pintarHoras(d); pintarCanales(d); pintarProductos(d); pintarFeed(d); pintarSemana(d); pintarEquipo(d); pintarWeb(d);
    vivo.classList.remove('caido'); $('#rd-vivo-txt').textContent = `En vivo · actualizado ${new Date().toLocaleTimeString('es-EC', { hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23', timeZone: window.RUI.TZ })}`;
    primera = false;
  }
  async function cargar() {
    const c = $('#rd-cuerpo'); if (document.hidden) return;
    try { c.classList.remove('rd-atenuado'); pintar(await window.REST.rpc('dashboard')); }
    catch (e) { vivo.classList.add('caido'); $('#rd-vivo-txt').textContent = 'Sin conexión: mostrando lo último'; c.classList.add('rd-atenuado'); if (/dueño|acceso|JWT|permission/i.test(e.message)) { window.REST.salir(); location.reload(); } }
  }


  /* ---- mini juego (módulo adicional): partidas, ganadores, códigos sin canjear y ajustes del dueño ---- */
  async function juego() {
    const art = $('#rd-juego'); if (!art || document.hidden) return;
    try {
      const j = await window.REST.rpc('juego_resumen'), tasa = j.semana.partidas ? Math.round(j.semana.ganadores / j.semana.partidas * 1000) / 10 : null;
      $('#rd-juego-cifras').innerHTML = [['Partidas hoy', num(j.hoy.partidas)], ['Ganadores hoy', `${num(j.hoy.ganadores)} de ${num(j.premios_dia_max)}`], ['Canjeados hoy', num(j.hoy.canjeados)],
        ['Gana 1 de cada…', tasa ? String(Math.round(100 / tasa)) : '—']].map(([a, b]) => `<div><span class="rotulo">${a}</span><b>${b}</b></div>`).join('') +
        (j.semana.invalidas ? `<div class="aviso"><span class="rotulo">Partidas sospechosas (7 días)</span><b>${num(j.semana.invalidas)}</b></div>` : '');
      $('#rd-juego-sub').textContent = `Premio: ${j.premio}. La semana: ${num(j.semana.partidas)} partidas, ${num(j.semana.ganadores)} ganadores.`;
      $('#rd-juego-pend').innerHTML = j.pendientes.length ? `<h3>Códigos por canjear</h3><ul>${j.pendientes.map(x => `<li><b>${esc(x.codigo)}</b> · ${esc(x.nombre)} · vence ${diaCorto(x.vence.slice(0, 10))}</li>`).join('')}</ul>` : '<p class="rest-sub">No hay premios esperando canje.</p>';
      const f = $('#rd-juego-cfg'); if (!f.dataset.listo) { f.dia.value = j.premios_dia_max; f.dif.value = j.dificultad <= 0.85 ? '0.7' : j.dificultad >= 1.15 ? '1.3' : '1'; f.on.checked = j.activo; f.dataset.listo = '1'; }
    } catch (e) { /* se reintenta */ }
  }
  const fj = $('#rd-juego-cfg');
  if (fj) fj.onsubmit = async e => { e.preventDefault(); try { await window.REST.rpc('juego_config_guardar', { p_activo: fj.on.checked, p_premio: null, p_premios_dia: parseInt(fj.dia.value, 10) || 0, p_dificultad: parseFloat(fj.dif.value) }); aviso('Ajustes del juego guardados.'); juego(); } catch (er) { aviso(er.message, true); } };

  /* ---- acciones ---- */
  function alEntrar() {
    $('#rd-app').hidden = false; cargar(); timer = setInterval(cargar, 4000); juego(); setInterval(juego, 15000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) cargar(); }); window.addEventListener('storage', cargar);
    if (window.REST.modo === 'demo') $('#rd-demo').hidden = false;
  }
  $('#rd-salir').onclick = () => { window.REST.salir(); location.reload(); };
  $('#rd-stock-abrir').onclick = () => { const f = $('#rd-editor'); f.hidden = !f.hidden; editando = !f.hidden; if (!f.hidden) { f.dataset.hecho = ''; armarEditor(D); $('input', f).focus(); } };
  $('#rd-editor').onsubmit = async e => {
    e.preventDefault(); const items = [...new FormData(e.target)].filter(([, v]) => v !== '').map(([producto, v]) => ({ producto, cantidad: parseInt(v, 10) }));
    if (!items.length) { aviso('Escribe al menos una cantidad.', true); return; }
    try { await window.REST.rpc('stock_fijar_varios', { p_items: items }); aviso('Stock de hoy guardado.'); e.target.hidden = true; editando = false; await cargar(); }
    catch (er) { aviso(er.message, true); }
  };
  $$('.rd-vistatabla').forEach(b => b.onclick = () => { const k = b.dataset.tabla, on = b.getAttribute('aria-pressed') !== 'true'; b.setAttribute('aria-pressed', on); b.textContent = on ? 'Ver gráfica' : 'Ver tabla'; $('#rd-' + k).hidden = on; $('#rd-' + k + '-tabla').hidden = !on; });
  const sim = async () => { try { const r = await window.REST.rpc('demo_simular'); if (r && r.n) { aviso(`Venta simulada: ${r.n} hamburguesa${r.n > 1 ? 's' : ''}.`); cargar(); } } catch (e) { aviso(e.message, true); } };
  $('#rd-sim').onclick = sim;
  $('#rd-auto').onclick = e => { const on = e.currentTarget.getAttribute('aria-pressed') !== 'true'; e.currentTarget.setAttribute('aria-pressed', on); e.currentTarget.textContent = on ? 'Detener simulación' : 'Simular ventas cada 6 s'; clearInterval(auto); if (on) { sim(); auto = setInterval(sim, 6000); } };
  $('#rd-reset').onclick = async () => { await window.REST.rpc('demo_reiniciar'); vistos = new Set(); primera = true; $('#rd-editor').dataset.hecho = ''; cargar(); aviso('Datos de ejemplo reiniciados.'); };

  window.RUI.sesion({ raiz: $('#rd-entrada'), roles: ['admin'], titulo: R.dashboard_txt.entrada_titulo, texto: R.dashboard_txt.entrada_texto, alEntrar });
})();

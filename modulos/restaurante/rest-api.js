/* Módulo de restaurante · puente único a la base: REST.rpc(función, args).
   Modo "demo": usa rest-mock.js (datos en el navegador, mismas funciones y respuestas que el SQL).
   Modo "supabase": llama a la API REST de Supabase con la clave anon o, si el personal entró, con su sesión. Nunca la clave service_role (§4.11).
   Configuración: window.RESTDATA.api = { modo: 'demo' | 'supabase', url, anonKey, schema }. */
(() => {
  const C = (window.RESTDATA && window.RESTDATA.api) || { modo: 'demo' };
  const demo = C.modo !== 'supabase';
  /* La sesión vive en sessionStorage (se cierra con la pestaña). La pantalla en tienda pone window.REST_PERSISTENTE = true antes de cargar este archivo:
     la tablet queda con su sesión aunque se cierre la app (localStorage). */
  const almacen = () => window.REST_PERSISTENTE ? localStorage : sessionStorage;
  const ss = { get: k => { try { return almacen().getItem(k); } catch (e) { return null; } }, set: (k, v) => { try { almacen().setItem(k, v); } catch (e) { /* sin almacenamiento */ } },
               del: k => { try { almacen().removeItem(k); } catch (e) { /* sin almacenamiento */ } } };

  async function refrescar() {
    const rt = ss.get('rest_refresh'); if (!rt) return false;
    const r = await fetch(`${C.url}/auth/v1/token?grant_type=refresh_token`, { method: 'POST', headers: { apikey: C.anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: rt }) });
    if (!r.ok) { cerrar(); return false; }
    guardar(await r.json()); return true;
  }
  function guardar(s) { ss.set('rest_jwt', s.access_token); ss.set('rest_refresh', s.refresh_token); }
  function cerrar() { ss.del('rest_jwt'); ss.del('rest_refresh'); ss.del('rest_yo'); ss.del('rest_demo'); }

  async function llamarSupabase(fn, args, reintento) {
    const jwt = ss.get('rest_jwt');
    let r;
    try {
      r = await fetch(`${C.url}/rest/v1/rpc/${fn}`, { method: 'POST', body: JSON.stringify(args || {}),
        headers: { apikey: C.anonKey, Authorization: 'Bearer ' + (jwt || C.anonKey), 'Content-Type': 'application/json', 'Content-Profile': C.schema, 'Accept-Profile': C.schema } });
    } catch (e) { throw new Error('Sin conexión. Revisa tu internet e inténtalo de nuevo.'); }
    if (r.status === 401 && jwt && !reintento && await refrescar()) return llamarSupabase(fn, args, true);
    const t = await r.text(); let d = null; try { d = t ? JSON.parse(t) : null; } catch (e) { /* respuesta no JSON */ }
    if (!r.ok) throw new Error((d && (d.message || d.error_description)) || 'No se pudo completar la acción.');
    return d;
  }

  const REST = {
    modo: demo ? 'demo' : 'supabase',
    rpc: (fn, args) => demo ? window.RESTMOCK.llamar(fn, args || {}) : llamarSupabase(fn, args),
    /* Personal: en demo se elige un usuario de ejemplo; en producción, correo y clave de Authentication (sin registro público, §4.10). */
    async entrar(correo, clave) {
      if (demo) return;
      const r = await fetch(`${C.url}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: C.anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: correo, password: clave }) });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(r.status === 400 ? 'Correo o clave incorrectos.' : (d.msg || d.error_description || 'No se pudo entrar.'));
      guardar(d);
    },
    entrarDemo(usuario) { ss.set('rest_demo', JSON.stringify(usuario)); },
    usuarioDemo() { try { return JSON.parse(ss.get('rest_demo') || 'null'); } catch (e) { return null; } },
    haySesion() { return demo ? !!REST.usuarioDemo() : !!ss.get('rest_jwt'); },
    salir: cerrar
  };
  window.REST = REST;
})();

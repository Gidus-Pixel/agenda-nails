/* Cloud dell'agenda — Cloudflare Worker + D1.
   Conserva SOLO dati cifrati sul dispositivo (AES-GCM, chiave derivata dalla password
   dell'estetista): il server non può leggere clienti, appuntamenti o foto.

   Variabili/segreti (wrangler):
   - ADMIN_TOKEN (segreto)   → protegge gli endpoint /admin (emissione codici di attivazione)
   - ORIGINI (facoltativa)   → elenco separato da virgole delle origini ammesse (CORS); vuota = tutte
*/
const VERSIONE_API = 1;
const MAX_CORPO = 12 * 1024 * 1024;      // 12 MB per richiesta
const MAX_RECORD_PUSH = 300;
const MAX_RECORD_DATI = 1_900_000;       // limite D1 per un singolo valore (circa 2 MB)
const DURATA_CODICE_MIN = 15;
const ALFABETO = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // senza 0/O, 1/I

export default {
  async fetch(req, env) {
    const cors = intestazioniCors(req, env);
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    try {
      const r = await instrada(req, env);
      for (const [k, v] of Object.entries(cors)) r.headers.set(k, v);
      return r;
    } catch (e) {
      const stato = e.stato || 500;
      if (stato === 500) console.error(e);
      return json({ errore: e.codice || 'errore', messaggio: stato === 500 ? 'Errore interno' : e.message }, stato, cors);
    }
  }
};

/* ---------------------------------------------------------------- utilità */
class ErroreHttp extends Error { constructor(stato, codice, messaggio) { super(messaggio); this.stato = stato; this.codice = codice; } }
const json = (dati, stato = 200, extra = {}) => new Response(JSON.stringify(dati), { status: stato, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...extra } });
const ora = () => new Date().toISOString();
function intestazioniCors(req, env) {
  const origine = req.headers.get('Origin') || '';
  const ammesse = String(env.ORIGINI || '').split(',').map((s) => s.trim()).filter(Boolean);
  const ok = !ammesse.length || ammesse.includes(origine);
  return {
    'Access-Control-Allow-Origin': ok ? (origine || '*') : 'null',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin'
  };
}
async function sha256(testo) {
  const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(testo));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
function casuale(n, alfabeto = null) {
  const b = crypto.getRandomValues(new Uint8Array(n));
  if (!alfabeto) return [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return [...b].map((x) => alfabeto[x % alfabeto.length]).join('');
}
const normCodice = (c) => String(c || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
function b64InBuf(s) { const bin = atob(s); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; }
function bufInB64(buf) { const u = new Uint8Array(buf); let s = ''; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000)); return btoa(s); }
async function leggiJson(req) {
  const len = Number(req.headers.get('Content-Length') || 0);
  if (len > MAX_CORPO) throw new ErroreHttp(413, 'troppo_grande', 'Richiesta troppo grande');
  const t = await req.text();
  if (t.length > MAX_CORPO) throw new ErroreHttp(413, 'troppo_grande', 'Richiesta troppo grande');
  try { return t ? JSON.parse(t) : {}; } catch (e) { throw new ErroreHttp(400, 'json', 'JSON non valido'); }
}
function testo(v, max = 200) { return String(v ?? '').slice(0, max); }

/* ---------------------------------------------------------------- autenticazione */
async function dispositivoDa(req, env) {
  const a = req.headers.get('Authorization') || '';
  const token = a.startsWith('Bearer ') ? a.slice(7).trim() : '';
  if (!token) throw new ErroreHttp(401, 'non_autorizzato', 'Dispositivo non collegato');
  const d = await env.DB.prepare(`SELECT d.id, d.spazio, d.nome, s.generazione, s.seq, l.revocata
      FROM dispositivi d JOIN spazi s ON s.id = d.spazio LEFT JOIN licenze l ON l.codice_hash = s.licenza_hash
      WHERE d.token_hash = ?`).bind(await sha256(token)).first();
  if (!d) throw new ErroreHttp(401, 'non_autorizzato', 'Dispositivo scollegato o codice non valido');
  if (d.revocata) throw new ErroreHttp(402, 'licenza_revocata', 'Abbonamento non attivo: contatta il fornitore dell\'app');
  await env.DB.prepare('UPDATE dispositivi SET ultimo = ? WHERE id = ?').bind(ora(), d.id).run();
  return d;
}
function admin(req, env) {
  const a = req.headers.get('Authorization') || '';
  if (!env.ADMIN_TOKEN || a !== `Bearer ${env.ADMIN_TOKEN}`) throw new ErroreHttp(401, 'non_autorizzato', 'Accesso amministratore negato');
}
async function nuovoDispositivo(env, spazio, nome) {
  const token = casuale(32);
  const id = crypto.randomUUID();
  await env.DB.prepare('INSERT INTO dispositivi (id, spazio, nome, token_hash, creato, ultimo) VALUES (?, ?, ?, ?, ?, ?)')
    .bind(id, spazio, testo(nome, 60), await sha256(token), ora(), ora()).run();
  return { dispositivoId: id, token };
}

/* ---------------------------------------------------------------- rotte */
async function instrada(req, env) {
  const url = new URL(req.url);
  const p = url.pathname.replace(/\/+$/, '') || '/';
  const m = req.method;

  if (p === '/' || p === '/v1') return json({ servizio: 'agenda-cloud', api: VERSIONE_API, stato: 'ok' });

  // Attivazione: crea lo spazio dell'attività con un codice di attivazione
  if (p === '/v1/attiva' && m === 'POST') {
    const b = await leggiJson(req);
    const codice = normCodice(b.licenza);
    if (!codice) throw new ErroreHttp(400, 'licenza_mancante', 'Inserisci il codice di attivazione');
    if (!b.sale || !b.verificatore) throw new ErroreHttp(400, 'dati_mancanti', 'Dati di cifratura mancanti');
    const h = await sha256(codice);
    const lic = await env.DB.prepare('SELECT * FROM licenze WHERE codice_hash = ?').bind(h).first();
    if (!lic || lic.revocata) throw new ErroreHttp(403, 'licenza_non_valida', 'Codice di attivazione non valido');
    if (lic.usati >= lic.max_spazi) throw new ErroreHttp(403, 'licenza_usata', 'Codice di attivazione già usato');
    const spazio = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare('UPDATE licenze SET usati = usati + 1 WHERE codice_hash = ?').bind(h),
      env.DB.prepare('INSERT INTO spazi (id, licenza_hash, sale, verificatore, generazione, seq, creato, aggiornato) VALUES (?, ?, ?, ?, 1, 0, ?, ?)')
        .bind(spazio, h, testo(b.sale, 200), testo(b.verificatore, 2000), ora(), ora())
    ]);
    const d = await nuovoDispositivo(env, spazio, b.nomeDispositivo);
    return json({ spazioId: spazio, ...d, generazione: 1 });
  }

  // Codice breve per collegare un altro dispositivo
  if (p === '/v1/collega/codice' && m === 'POST') {
    const d = await dispositivoDa(req, env);
    const codice = casuale(10, ALFABETO);
    const scade = new Date(Date.now() + DURATA_CODICE_MIN * 60000).toISOString();
    await env.DB.batch([
      env.DB.prepare('DELETE FROM codici WHERE spazio = ? OR scade < ?').bind(d.spazio, ora()),
      env.DB.prepare('INSERT INTO codici (codice_hash, spazio, scade) VALUES (?, ?, ?)').bind(await sha256(codice), d.spazio, scade)
    ]);
    return json({ codice: `${codice.slice(0, 5)}-${codice.slice(5)}`, scade });
  }
  if (p === '/v1/collega' && m === 'POST') {
    const b = await leggiJson(req);
    const codice = normCodice(b.codice);
    if (codice.length !== 10) throw new ErroreHttp(400, 'codice_non_valido', 'Il codice è di 10 caratteri');
    const h = await sha256(codice);
    const c = await env.DB.prepare('SELECT * FROM codici WHERE codice_hash = ?').bind(h).first();
    if (!c || c.scade < ora()) throw new ErroreHttp(403, 'codice_non_valido', 'Codice non valido o scaduto: generane uno nuovo');
    await env.DB.prepare('DELETE FROM codici WHERE codice_hash = ?').bind(h).run(); // monouso
    const s = await env.DB.prepare('SELECT id, sale, verificatore, generazione FROM spazi WHERE id = ?').bind(c.spazio).first();
    if (!s) throw new ErroreHttp(404, 'spazio', 'Spazio non trovato');
    const d = await nuovoDispositivo(env, s.id, b.nomeDispositivo);
    return json({ spazioId: s.id, ...d, sale: s.sale, verificatore: s.verificatore, generazione: s.generazione });
  }

  if (p === '/v1/stato' && m === 'GET') {
    const d = await dispositivoDa(req, env);
    const disp = await env.DB.prepare('SELECT id, nome, creato, ultimo FROM dispositivi WHERE spazio = ? ORDER BY creato').bind(d.spazio).all();
    const uso = await env.DB.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(LENGTH(dati)), 0) AS byte FROM record WHERE spazio = ?').bind(d.spazio).first();
    const s = await env.DB.prepare('SELECT sale, verificatore FROM spazi WHERE id = ?').bind(d.spazio).first();
    return json({ spazioId: d.spazio, dispositivoId: d.id, generazione: d.generazione, seq: d.seq, record: uso.n, byte: uso.byte, dispositivi: disp.results, sale: s.sale, verificatore: s.verificatore });
  }

  // Invio delle modifiche (record già cifrati)
  if (p === '/v1/push' && m === 'POST') {
    const d = await dispositivoDa(req, env);
    const b = await leggiJson(req);
    if (Number(b.generazione) !== d.generazione) throw new ErroreHttp(409, 'generazione', 'I dati nel cloud sono stati sostituiti da un altro dispositivo');
    const recs = Array.isArray(b.record) ? b.record : [];
    if (!recs.length) return json({ seq: d.seq });
    if (recs.length > MAX_RECORD_PUSH) throw new ErroreHttp(413, 'troppi', 'Troppi record in una volta');
    const righe = recs.map((r) => {
      const k = testo(r.k, 100); const dati = b64InBuf(String(r.d || ''));
      if (!k || !dati.length) throw new ErroreHttp(400, 'record', 'Record non valido');
      if (dati.length > MAX_RECORD_DATI) throw new ErroreHttp(413, 'record_grande', 'Un elemento è troppo grande');
      return { k, dati };
    });
    const fine = await env.DB.prepare('UPDATE spazi SET seq = seq + ?, aggiornato = ? WHERE id = ? AND generazione = ? RETURNING seq')
      .bind(righe.length, ora(), d.spazio, d.generazione).first();
    if (!fine) throw new ErroreHttp(409, 'generazione', 'I dati nel cloud sono stati sostituiti da un altro dispositivo');
    const primo = fine.seq - righe.length + 1;
    await env.DB.batch(righe.map((r, i) => env.DB.prepare(
      'INSERT INTO record (spazio, chiave, seq, dati) VALUES (?, ?, ?, ?) ON CONFLICT(spazio, chiave) DO UPDATE SET seq = excluded.seq, dati = excluded.dati'
    ).bind(d.spazio, r.k, primo + i, r.dati)));
    return json({ seq: fine.seq });
  }

  // Ricezione delle modifiche successive a "dopo"
  if (p === '/v1/pull' && m === 'GET') {
    const d = await dispositivoDa(req, env);
    const dopo = Math.max(0, Number(url.searchParams.get('dopo')) || 0);
    const limite = Math.min(500, Math.max(1, Number(url.searchParams.get('limite')) || 200));
    const maxByte = 8 * 1024 * 1024;
    const r = await env.DB.prepare('SELECT chiave, seq, dati FROM record WHERE spazio = ? AND seq > ? ORDER BY seq LIMIT ?').bind(d.spazio, dopo, limite).all();
    const out = []; let byte = 0;
    for (const x of r.results) {
      const len = x.dati.byteLength ?? x.dati.length;
      if (out.length && byte + len > maxByte) break;
      out.push({ k: x.chiave, s: x.seq, d: bufInB64(x.dati) }); byte += len;
    }
    const ultimo = out.length ? out[out.length - 1].s : dopo;
    return json({ generazione: d.generazione, record: out, ultimo, altri: out.length < r.results.length || r.results.length === limite });
  }

  // Sostituzione completa (ripristino di un backup o nuova password): svuota il cloud e cambia generazione
  if (p === '/v1/reset' && m === 'POST') {
    const d = await dispositivoDa(req, env);
    const b = await leggiJson(req);
    if (!b.sale || !b.verificatore) throw new ErroreHttp(400, 'dati_mancanti', 'Dati di cifratura mancanti');
    const res = await env.DB.batch([
      env.DB.prepare('DELETE FROM record WHERE spazio = ?').bind(d.spazio),
      env.DB.prepare('UPDATE spazi SET generazione = generazione + 1, seq = 0, sale = ?, verificatore = ?, aggiornato = ? WHERE id = ? RETURNING generazione')
        .bind(testo(b.sale, 200), testo(b.verificatore, 2000), ora(), d.spazio)
    ]);
    return json({ generazione: res[1].results[0].generazione });
  }

  const mDisp = p.match(/^\/v1\/dispositivi\/([\w-]+)$/);
  if (mDisp && m === 'DELETE') {
    const d = await dispositivoDa(req, env);
    await env.DB.prepare('DELETE FROM dispositivi WHERE id = ? AND spazio = ?').bind(mDisp[1], d.spazio).run();
    return json({ ok: true });
  }

  /* ---------------- amministrazione (solo per il fornitore dell'app) ---------------- */
  if (p === '/admin/licenze' && m === 'POST') {
    admin(req, env);
    const b = await leggiJson(req);
    const codice = casuale(12, ALFABETO);
    await env.DB.prepare('INSERT INTO licenze (codice_hash, nota, max_spazi, creato) VALUES (?, ?, ?, ?)')
      .bind(await sha256(codice), testo(b.nota, 120), Math.max(1, Number(b.maxSpazi) || 1), ora()).run();
    return json({ codice: codice.match(/.{4}/g).join('-'), nota: testo(b.nota, 120) });
  }
  if (p === '/admin/spazi' && m === 'GET') {
    admin(req, env);
    const r = await env.DB.prepare(`SELECT s.id, s.creato, s.aggiornato, s.generazione, l.nota, l.revocata,
        (SELECT COUNT(*) FROM dispositivi d WHERE d.spazio = s.id) AS dispositivi,
        (SELECT COALESCE(SUM(LENGTH(dati)), 0) FROM record r WHERE r.spazio = s.id) AS byte,
        (SELECT MAX(ultimo) FROM dispositivi d WHERE d.spazio = s.id) AS ultimo_accesso
      FROM spazi s LEFT JOIN licenze l ON l.codice_hash = s.licenza_hash ORDER BY s.creato`).all();
    return json({ spazi: r.results });
  }
  const mRev = p.match(/^\/admin\/spazi\/([\w-]+)\/(sospendi|riattiva)$/);
  if (mRev && m === 'POST') {
    admin(req, env);
    const s = await env.DB.prepare('SELECT licenza_hash FROM spazi WHERE id = ?').bind(mRev[1]).first();
    if (!s) throw new ErroreHttp(404, 'spazio', 'Spazio non trovato');
    await env.DB.prepare('UPDATE licenze SET revocata = ? WHERE codice_hash = ?').bind(mRev[2] === 'sospendi' ? 1 : 0, s.licenza_hash).run();
    return json({ ok: true });
  }
  const mDel = p.match(/^\/admin\/spazi\/([\w-]+)$/);
  if (mDel && m === 'DELETE') {
    admin(req, env);
    await env.DB.batch([
      env.DB.prepare('DELETE FROM record WHERE spazio = ?').bind(mDel[1]),
      env.DB.prepare('DELETE FROM dispositivi WHERE spazio = ?').bind(mDel[1]),
      env.DB.prepare('DELETE FROM codici WHERE spazio = ?').bind(mDel[1]),
      env.DB.prepare('DELETE FROM spazi WHERE id = ?').bind(mDel[1])
    ]);
    return json({ ok: true });
  }

  throw new ErroreHttp(404, 'non_trovato', 'Indirizzo non trovato');
}

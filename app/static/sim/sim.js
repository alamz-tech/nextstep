// NextStep web simulator. Renders messages from the server-side engine.
// Messages carry copy refs, so switching language re-renders the whole transcript.
(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const S = { copy: null, lang: 'en', msgs: [], sid: null, busy: false, voice: null,
    counts: { conv: 0, checks: 0, refs: 0, visits: 0, crisis: 0 } };
  const EV = { conversation_started: 'conv', check_completed: 'checks', referral_given: 'refs', visit_confirmed: 'visits', crisis_escalation: 'crisis' };

  const t = (ref, params) => {
    if (!S.copy || !ref) return '';
    const f = S.copy[ref[0]] || {};
    let s = ((f[S.lang] || {})[ref[1]]) || ((f.en || {})[ref[1]]) || '';
    if (params) for (const k in params) s = s.split('{' + k + '}').join(params[k]);
    return s;
  };
  const txt = (m) => (m.texts ? (m.texts[S.lang] || m.texts.en || Object.values(m.texts)[0] || '') : t(m.ref, m.params));
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
  const bars = (n, k) => { const w = el('span', 'bars'); w.setAttribute('aria-hidden', 'true'); for (let i = 0; i < n; i++) { const b = el('span'); b.style.height = (5 + Math.round(Math.abs(Math.sin((i + 1) * k)) * 17)) + 'px'; w.appendChild(b); } return w; };

  function sid() {
    try { const v = sessionStorage.getItem('ns-sid'); if (v) return v; } catch (e) {}
    const v = (crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2) + Date.now()).replace(/-/g, '');
    try { sessionStorage.setItem('ns-sid', v); } catch (e) {}
    return v;
  }

  async function post(path, body) {
    const r = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  }

  async function send(payload, userMsg) {
    if (S.busy) return;
    S.busy = true;
    if (userMsg) S.msgs.push(userMsg);
    render();
    try {
      const data = await post('/sim/api/message', Object.assign({ sid: S.sid }, payload));
      apply(data);
    } catch (e) {
      S.msgs.push({ from: 'sys', texts: { en: 'Could not reach the NextStep server.' } });
    } finally { S.busy = false; render(); }
  }

  function apply(data) {
    for (const m of data.messages) S.msgs.push(Object.assign({ from: m.kind === 'system' ? 'sys' : 'bot' }, m));
    for (const e of data.events || []) if (EV[e]) S.counts[EV[e]]++;
    if (data.lang && data.lang !== S.lang) setLang(data.lang, false);
    if (data.voice) S.voice = data.voice;
  }

  function render() {
    const log = $('log');
    log.textContent = '';
    if (!S.copy) { log.appendChild(el('div', 'status', 'Loading…')); return; }
    let last = -1;
    S.msgs.forEach((m, i) => { if (m.from === 'bot' && ((m.buttons && m.buttons.length) || m.list)) last = i; });
    S.msgs.forEach((m, i) => log.appendChild(renderMsg(m, i === last && !S.busy)));
    renderCounters();
    log.scrollTop = log.scrollHeight;
  }

  function renderMsg(m, active) {
    if (m.from === 'sys') return el('div', 'sys', txt(m));
    if (m.from === 'user') {
      if (m.voice) {
        const w = el('div', 'uv');
        const wave = el('div', 'wave');
        wave.appendChild(iconMic()); wave.appendChild(bars(20, 1.7)); wave.appendChild(el('span', null, '0:04'));
        wave.setAttribute('aria-label', 'Voice note');
        w.appendChild(wave); w.appendChild(el('em', null, '"' + txt(m) + '"'));
        return w;
      }
      return el('div', 'u', txt(m));
    }
    const w = el('div', 'b');
    const bub = el('div', 'bubble' + (m.safety ? ' safety' : ''));
    if (m.kind === 'card' && m.card) {
      const head = el('div', 'card-head');
      head.appendChild(el('strong', null, t(['referral', 'card_image_label'])));
      const tags = el('span', 'tags');
      if (m.card.is_free) tags.appendChild(el('span', 'tag free', t(['referral', 'tag_free'])));
      if (m.card.youth_friendly) tags.appendChild(el('span', 'tag youth', t(['referral', 'tag_youth'])));
      head.appendChild(tags); bub.appendChild(head);
      const body = el('div', 'card-body');
      if (m.card.demo_tag_ref) body.appendChild(el('span', 'demo-tag', t(m.card.demo_tag_ref)));
      body.appendChild(el('span', 'name', m.card.name));
      body.appendChild(el('span', null, m.card.address));
      body.appendChild(el('span', null, m.card.hours_raw));
      body.appendChild(el('strong', null, t(['referral', 'expect_title'])));
      bub.appendChild(body);
    }
    if (m.audio) {
      const v = el('div', 'voice');
      const a = document.createElement('audio'); a.controls = true; a.src = m.audio; a.setAttribute('aria-label', t(['qa', 'voice_label']));
      v.appendChild(a); bub.appendChild(v);
    }
    const body = txt(m);
    if (body) {
      const bt = el('div', 'btext');
      if (m.kicker) bt.appendChild(el('span', 'kicker', t(['check', 'progress']).replace('{n}', m.kicker)));
      bt.appendChild(el('span', 't', body));
      bub.appendChild(bt);
    }
    w.appendChild(bub);
    if (m.buttons && m.buttons.length) {
      const o = el('div', 'opts');
      for (const b of m.buttons) {
        const btn = el('button', null, t(b.ref)); btn.type = 'button'; btn.disabled = !active;
        btn.addEventListener('click', () => clickButton(b));
        o.appendChild(btn);
      }
      w.appendChild(o);
    }
    if (m.list) {
      const lst = el('div', 'rows'); lst.setAttribute('role', 'group'); lst.setAttribute('aria-label', t(['global', 'list_button']));
      for (const r of m.list) {
        const btn = el('button'); btn.type = 'button'; btn.disabled = !active;
        btn.appendChild(el('span', 'rt', t(r.ref))); btn.appendChild(el('span', 'rd', t(r.desc_ref)));
        btn.addEventListener('click', () => clickButton({ id: r.id, ref: r.ref }));
        lst.appendChild(btn);
      }
      w.appendChild(lst);
    }
    const chips = el('span', 'chips');
    if (m.draft) chips.appendChild(el('span', 'chip draft', 'DRAFT · clinician review'));
    if (m.safety) chips.appendChild(el('span', 'chip safe', 'Safety response'));
    if (m.voice_fallback) chips.appendChild(el('span', 'src', 'Voice reply off for this language (text only)'));
    if (m.chunk) chips.appendChild(el('span', 'src', 'Answer bank: ' + m.chunk.ids.join(', ') + (m.chunk.source.indexOf('TODO') >= 0 ? ' · source citation TODO' : ' · ' + m.chunk.source)));
    if (chips.childNodes.length) w.appendChild(chips);
    return w;
  }

  function iconMic() {
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('width', '20'); s.setAttribute('height', '20'); s.setAttribute('viewBox', '0 0 24 24'); s.setAttribute('aria-hidden', 'true');
    s.setAttribute('fill', 'none'); s.setAttribute('stroke', 'currentColor'); s.setAttribute('stroke-width', '2'); s.setAttribute('stroke-linecap', 'round');
    const p = document.createElementNS(ns, 'path'); p.setAttribute('d', 'M9 6a3 3 0 016 0v5a3 3 0 01-6 0z M5 11a7 7 0 0014 0 M12 18v3'); s.appendChild(p);
    return s;
  }

  function clickButton(b) {
    send({ kind: 'button', button: b.id }, { from: 'user', ref: b.ref });
  }
  function sendText(text, ref) {
    if (!text) return;
    send({ kind: 'text', text }, ref ? { from: 'user', ref } : { from: 'user', texts: { en: text } });
  }
  function sendVoice() {
    const ref = ['qa', 'user_voice'];
    send({ kind: 'voice', text: t(ref) }, { from: 'user', ref, voice: true });
  }
  async function advance() {
    if (S.busy) return;
    S.busy = true;
    try { apply(await post('/sim/api/advance', { sid: S.sid })); } finally { S.busy = false; render(); }
  }

  function renderCounters() {
    const c = $('counters'); c.textContent = '';
    const k = S.counts;
    [['Conversations', k.conv], ['Private checks', k.checks], ['Referrals given', k.refs], ['Visits confirmed', k.visits], ['Crisis escalations', k.crisis]]
      .forEach(([label, v]) => { const d = el('div', 'counter'); d.appendChild(el('b', null, String(v))); d.appendChild(el('span', null, label)); c.appendChild(d); });
  }

  function shortcuts() {
    const box = $('shortcuts'); box.textContent = '';
    const typeIt = (flow, key) => () => sendText(t([flow, key]), [flow, key]);
    [
      ['Voice: kissing question', sendVoice],
      ['Private check', () => clickButton({ id: 'menu_check', ref: ['menu', 'row_check'] })],
      ['Find a service', () => clickButton({ id: 'menu_find', ref: ['menu', 'row_find'] })],
      ['Skip 3 days (follow-up)', advance],
      ['Crisis: violence', typeIt('crisis', 'user_violence')],
      ['Crisis: self-harm', typeIt('crisis', 'user_selfharm')],
      ['Dose question', typeIt('cant_help', 'user_dose')],
      ['Off-topic', typeIt('cant_help', 'user_offtopic')],
    ].forEach(([label, fn]) => { const b = el('button', null, label); b.type = 'button'; b.addEventListener('click', fn); box.appendChild(b); });
  }

  function setLang(l, rerender = true) {
    S.lang = l;
    document.documentElement.lang = l === 'pcm' ? 'pcm' : 'en';
    $('lang-en').setAttribute('aria-pressed', String(l === 'en'));
    $('lang-pcm').setAttribute('aria-pressed', String(l === 'pcm'));
    const sim = (S.copy && S.copy.sim && S.copy.sim[l]) || {};
    $('banner').textContent = sim.banner || $('banner').textContent;
    $('ns-input').placeholder = sim.placeholder || 'Type a message';
    $('send-label').textContent = sim.send || 'Send';
    $('restart-label').textContent = sim.restart || 'Restart';
    $('voice').setAttribute('aria-label', sim.voice || 'Send demo voice note');
    $('voice').title = sim.voice || 'Send demo voice note';
    if (rerender) render();
  }

  function setTheme(dark) {
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    $('theme').setAttribute('aria-pressed', String(dark));
    $('theme-label').textContent = dark ? 'Light' : 'Dark';
  }

  async function restart() {
    try { await post('/sim/api/restart', { sid: S.sid }); } catch (e) {}
    try { sessionStorage.removeItem('ns-sid'); } catch (e) {}
    S.sid = sid(); S.msgs = [];
    S.counts = { conv: 0, checks: 0, refs: 0, visits: 0, crisis: 0 };
    sendText('Hi', ['sim', 'say_hi']);
  }

  async function init() {
    S.sid = sid();
    const dark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    setTheme(dark);
    $('lang-en').addEventListener('click', () => setLang('en'));
    $('lang-pcm').addEventListener('click', () => setLang('pcm'));
    $('theme').addEventListener('click', () => setTheme($('theme').getAttribute('aria-pressed') !== 'true'));
    $('restart').addEventListener('click', restart);
    $('voice').addEventListener('click', sendVoice);
    $('composer').addEventListener('submit', (e) => { e.preventDefault(); const v = $('ns-input').value.trim(); $('ns-input').value = ''; sendText(v); });
    try {
      S.copy = await (await fetch('/sim/api/copy')).json();
    } catch (e) { $('status').textContent = 'Could not load copy.'; return; }
    setLang('en', false);
    shortcuts();
    try { const h = await (await fetch('/healthz')).json(); $('engine-info').textContent = `Engine: LLM ${h.llm}, voice ${h.voice}.`; } catch (e) {}
    await post('/sim/api/restart', { sid: S.sid }).catch(() => {});
    sendText('Hi', ['sim', 'say_hi']);
  }
  init();
})();

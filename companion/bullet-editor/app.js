/* RR bullet-data editor (companion tool, not part of the game export).
 * Read: data.json on feat/gameplay-redo via raw.githubusercontent (no API quota)
 *       + GitHub Contents API (ETag revalidate) when quota allows; newest updated_at wins.
 * Write: no secret in this page. Submit opens GitHub's "new file" page pre-filled with
 *       inbox/<id>.json; one "Commit changes" tap by a logged-in owner commits it, and
 *       .github/workflows/bullet-editor-ingest.yml merges inbox files into data.json.
 */
(function () {
  'use strict';
  var OWNER = 'pineapplecat123', REPO = 'revolver-rush', BRANCH = 'feat/gameplay-redo';
  var DIR = 'companion/bullet-editor';
  var GATE = '6f1e76e002ffa351d514e393ef9b95a13a7609ae91688194a62dc5a3903afd32';
  var SALT = 'rr-bullets-v1:';
  var POLL_MS = 10000, API_EVERY_MS = 60000, STALE_PENDING_MS = 20 * 60 * 1000;
  var K_UNLOCK = 'rrb_unlock', K_PENDING = 'rrb_pending', K_DRAFT = 'rrb_draft';

  var RAW_URL = 'https://raw.githubusercontent.com/' + OWNER + '/' + REPO + '/' + BRANCH + '/' + DIR + '/data.json';
  var API_URL = 'https://api.github.com/repos/' + OWNER + '/' + REPO + '/contents/' + DIR + '/data.json?ref=' + encodeURIComponent(BRANCH);
  var NEW_URL = 'https://github.com/' + OWNER + '/' + REPO + '/new/' + BRANCH + '/' + DIR + '/inbox';

  var $ = function (id) { return document.getElementById(id); };
  var doc = null, docKey = '', lastOk = 0, lastApi = 0, apiRemaining = null, apiResetAt = 0;
  var filter = 'all', timer = null, busy = false, flashIds = {};
  var pending = load(K_PENDING, []);

  function load(k, d) { try { var v = JSON.parse(localStorage.getItem(k)); return v == null ? d : v; } catch (e) { return d; } }
  function save(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function sh(d) { return new Date(d.getTime() + 8 * 3600 * 1000); } // shift to UTC+8, read with getUTC*
  function iso8(d) { var s = sh(d); return s.getUTCFullYear() + '-' + pad(s.getUTCMonth() + 1) + '-' + pad(s.getUTCDate()) + 'T' + pad(s.getUTCHours()) + ':' + pad(s.getUTCMinutes()) + ':' + pad(s.getUTCSeconds()) + '+08:00'; }
  function hms(d) { var s = sh(d); return pad(s.getUTCHours()) + ':' + pad(s.getUTCMinutes()) + ':' + pad(s.getUTCSeconds()); }
  function shortTime(isoStr) { var t = Date.parse(isoStr); if (!t) return ''; var s = sh(new Date(t)); return (s.getUTCMonth() + 1) + '/' + s.getUTCDate() + ' ' + pad(s.getUTCHours()) + ':' + pad(s.getUTCMinutes()); }
  function newId() { var s = sh(new Date()); return 'b' + s.getUTCFullYear() + pad(s.getUTCMonth() + 1) + pad(s.getUTCDate()) + '-' + pad(s.getUTCHours()) + pad(s.getUTCMinutes()) + pad(s.getUTCSeconds()) + '-' + Math.random().toString(36).slice(2, 6); }
  function norm(s) { return String(s || '').trim().toLowerCase(); }

  // ---------- gate ----------
  function normPin(s) { return String(s || '').normalize('NFC').trim().replace(/[０-９]/g, function (c) { return String.fromCharCode(c.charCodeAt(0) - 0xFEE0); }); }
  function sha256hex(text) {
    if (!(window.crypto && crypto.subtle)) return Promise.reject(new Error('no-subtle'));
    return crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)).then(function (buf) {
      return Array.prototype.map.call(new Uint8Array(buf), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
    });
  }
  function unlock() { $('gate').classList.add('hidden'); $('app').classList.remove('hidden'); start(); }
  $('gateForm').addEventListener('submit', function (e) {
    e.preventDefault();
    sha256hex(SALT + normPin($('pin').value)).then(function (h) {
      if (h === GATE) { save(K_UNLOCK, h); unlock(); } else { $('pinErr').classList.remove('hidden'); $('pin').select(); }
    }, function () { $('pinErr').textContent = '浏览器不支持校验，请用 https 打开'; $('pinErr').classList.remove('hidden'); });
  });
  if (load(K_UNLOCK, '') === GATE) unlock(); else setTimeout(function () { $('pin').focus(); }, 50);

  // ---------- data ----------
  function parseDoc(text) {
    var d = JSON.parse(text);
    if (!d || !Array.isArray(d.bullets)) throw new Error('bad-doc');
    return d;
  }
  function stamp(d) { return Date.parse(d && d.updated_at) || 0; }
  function fetchRaw() {
    return fetch(RAW_URL + '?t=' + Date.now(), { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('raw ' + r.status); return r.text();
    }).then(parseDoc);
  }
  function fetchApi() {
    lastApi = Date.now();
    return fetch(API_URL, { cache: 'no-cache', headers: { Accept: 'application/vnd.github.raw+json' } }).then(function (r) {
      var rem = r.headers.get('X-RateLimit-Remaining'), rs = r.headers.get('X-RateLimit-Reset');
      if (rem != null) apiRemaining = +rem;
      if (rs) apiResetAt = (+rs) * 1000;
      if (!r.ok) throw new Error('api ' + r.status);
      return r.text();
    }).then(parseDoc);
  }
  function fetchLocal() { return fetch('data.json?t=' + Date.now(), { cache: 'no-store' }).then(function (r) { if (!r.ok) throw new Error('local'); return r.text(); }).then(parseDoc); }
  function apiAllowed() {
    if (apiRemaining == null) return true;
    if (Date.now() > apiResetAt) return true;
    return apiRemaining > 15;
  }

  function refresh(forceApi) {
    if (busy) return; busy = true;
    var wantApi = apiAllowed() && (forceApi || pending.length > 0 || !doc || Date.now() - lastApi >= API_EVERY_MS);
    var jobs = [fetchRaw().catch(function () { return null; })];
    if (wantApi) jobs.push(fetchApi().catch(function () { return null; }));
    Promise.all(jobs).then(function (rs) {
      var best = null;
      rs.forEach(function (d) { if (d && (!best || stamp(d) >= stamp(best))) best = d; });
      if (!best && !doc) return fetchLocal().catch(function () { return null; });
      return best;
    }).then(function (best) {
      busy = false;
      if (best && (!doc || stamp(best) >= stamp(doc))) apply(best);
      if (best || doc) { if (best) lastOk = Date.now(); setStatus(true); } else setStatus(false);
    }, function () { busy = false; setStatus(false); });
  }

  function apply(d) {
    var key = JSON.stringify(d.bullets);
    if (doc) {
      var prev = {}; doc.bullets.forEach(function (b) { prev[b.id] = b; });
      d.bullets.forEach(function (b) { var p = prev[b.id]; if (p && !p.in_game && b.in_game) flashIds[b.id] = 1; });
    }
    var have = {}; d.bullets.forEach(function (b) { have[b.id] = b; });
    var arrived = pending.filter(function (p) { return have[p.rec.id]; });
    if (arrived.length) {
      arrived.forEach(function (p) { flashIds[p.rec.id] = 1; });
      pending = pending.filter(function (p) { return !have[p.rec.id]; });
      save(K_PENDING, pending);
      showNotice('ok', '「' + esc(arrived.map(function (p) { return p.rec.name; }).join('、')) + '」已收录到云端，状态：未入库。');
    }
    doc = d;
    if (key !== docKey || arrived.length || Object.keys(flashIds).length) { docKey = key; render(); }
    fillTypes(); checkDup();
  }

  function setStatus(ok) {
    var el = $('syncStatus');
    el.classList.toggle('err', !ok);
    var extra = pending.length ? ' · 有 ' + pending.length + ' 颗等待确认' : '';
    el.innerHTML = '<span class="dot"></span>' + (ok
      ? '上次刷新 ' + hms(new Date(lastOk || Date.now())) + ' · 每 10 秒自动刷新' + extra
      : '暂时读不到云端数据，稍后自动重试' + extra);
  }

  // ---------- render ----------
  function itemHtml(b, pend) {
    var badge = pend ? '<span class="badge pend">等待确认</span>'
      : (b.in_game ? '<span class="badge in">已入库</span>' : '<span class="badge out">未入库</span>');
    var meta = [];
    meta.push('<span>类型 <b>' + (b.type ? esc(b.type) : '—') + '</b></span>');
    meta.push('<span>伤害 <b>' + (b.damage !== '' && b.damage != null ? esc(b.damage) : '—') + '</b></span>');
    meta.push('<span>稀有度 <b>' + (b.rarity ? esc(b.rarity) : '—') + '</b></span>');
    var h = '<div class="item' + (flashIds[b.id] ? ' flash' : '') + '"><div class="top"><div class="name">' + esc(b.name) + '</div>' + badge + '</div>';
    h += '<div class="meta">' + meta.join('') + '</div>';
    if (b.effect) h += '<div class="desc">' + esc(b.effect) + '</div>';
    if (b.notes) h += '<div class="desc note">备注：' + esc(b.notes) + '</div>';
    var t = shortTime(b.updated_at || b.created_at);
    if (t && !pend) h += '<div class="meta">更新于 ' + esc(t) + '</div>';
    return h + '</div>';
  }
  function pendingHtml(p) {
    var h = itemHtml(p.rec, true);
    var stale = Date.now() - p.at > STALE_PENDING_MS;
    var tail = '<div class="meta">' + (stale ? '还没收到，可能 GitHub 页面没点「Commit changes」' : '提交于 ' + hms(new Date(p.at)) + '，确认后约 10–60 秒出现') + '</div>' +
      '<div class="actions"><a class="btn small" href="' + esc(p.url) + '" target="_blank" rel="noopener">重新打开确认页</a>' +
      '<button type="button" class="small" data-drop="' + esc(p.rec.id) + '">移除</button></div>';
    return h.replace(/<\/div>$/, tail + '</div>');
  }
  function render() {
    var list = doc ? doc.bullets.slice() : [];
    list.sort(function (a, b) { return (Date.parse(b.created_at) || 0) - (Date.parse(a.created_at) || 0); });
    var nIn = list.filter(function (b) { return b.in_game; }).length;
    $('count').textContent = list.length ? '共 ' + list.length + ' 颗 · 已入库 ' + nIn + ' · 未入库 ' + (list.length - nIn) : '';
    var shown = list.filter(function (b) { return filter === 'all' || (filter === 'in' ? b.in_game : !b.in_game); });
    var html = '';
    if (filter !== 'in') pending.forEach(function (p) { html += pendingHtml(p); });
    shown.forEach(function (b) { html += itemHtml(b, false); });
    if (!html) {
      html = !doc ? '<div class="empty">正在读取云端数据…</div>'
        : list.length === 0 ? '<div class="empty"><div class="big">🔫</div>还没有子弹，<br>在上面写第一颗吧～</div>'
        : '<div class="empty">这一栏暂时是空的</div>';
    }
    $('list').innerHTML = html;
    flashIds = {};
    setStatus(!!doc);
  }
  $('list').addEventListener('click', function (e) {
    var id = e.target && e.target.getAttribute && e.target.getAttribute('data-drop');
    if (!id) return;
    pending = pending.filter(function (p) { return p.rec.id !== id; }); save(K_PENDING, pending); render();
  });
  $('tabs').addEventListener('click', function (e) {
    var f = e.target && e.target.getAttribute('data-f'); if (!f) return;
    filter = f;
    Array.prototype.forEach.call($('tabs').children, function (b) { b.classList.toggle('on', b.getAttribute('data-f') === f); });
    render();
  });

  // ---------- form ----------
  var FIELDS = ['name', 'type', 'damage', 'rarity', 'effect', 'notes'];
  function formVals() { var v = {}; FIELDS.forEach(function (f) { v[f] = $('f_' + f).value.trim(); }); return v; }
  (function restoreDraft() { var d = load(K_DRAFT, null); if (d) FIELDS.forEach(function (f) { if (d[f]) $('f_' + f).value = d[f]; }); })();
  $('bulletForm').addEventListener('input', function () { save(K_DRAFT, formVals()); checkDup(); $('formErr').classList.add('hidden'); });

  function fillTypes() {
    var seen = {}, html = '';
    (doc ? doc.bullets : []).forEach(function (b) { var t = (b.type || '').trim(); if (t && !seen[t]) { seen[t] = 1; html += '<option value="' + esc(t) + '"></option>'; } });
    if ($('typeList').innerHTML !== html) $('typeList').innerHTML = html;
  }
  function checkDup() {
    var n = norm($('f_name').value), el = $('dupHint');
    if (!n) { el.classList.add('hidden'); return; }
    var all = (doc ? doc.bullets : []).concat(pending.map(function (p) { return p.rec; }));
    var hit = all.filter(function (b) { return norm(b.name) === n; }).length;
    if (hit) { el.textContent = '已经有 ' + hit + ' 颗同名的子弹，仍然可以提交，会另外新增一条。'; el.classList.remove('hidden'); }
    else el.classList.add('hidden');
  }
  function showNotice(kind, html) { var el = $('submitNotice'); el.className = 'notice' + (kind === 'ok' ? ' ok' : ''); el.innerHTML = html; }

  $('bulletForm').addEventListener('submit', function (e) {
    e.preventDefault();
    var v = formVals();
    if (!v.name) { $('formErr').textContent = '名称必须填写'; $('formErr').classList.remove('hidden'); $('f_name').focus(); return; }
    var now = iso8(new Date());
    var rec = { id: newId(), name: v.name, type: v.type, damage: v.damage, rarity: v.rarity, effect: v.effect, notes: v.notes, in_game: false, created_at: now, updated_at: now };
    var url = NEW_URL + '?filename=' + encodeURIComponent(rec.id + '.json') + '&value=' + encodeURIComponent(JSON.stringify(rec, null, 2) + '\n');
    var win = null;
    try { win = window.open(url, '_blank'); if (win) win.opener = null; } catch (err) {}
    pending.unshift({ rec: rec, url: url, at: Date.now() }); save(K_PENDING, pending);
    $('bulletForm').reset(); save(K_DRAFT, null); checkDup();
    showNotice('', '<b>「' + esc(rec.name) + '」还差一步：</b>在打开的 GitHub 页面点绿色的「Commit changes」按钮（第一次需要先登录 GitHub）。确认后这里会自动显示，一般 10–60 秒。' +
      (win ? '' : '<br>页面没自动打开？<a href="' + esc(url) + '" target="_blank" rel="noopener">点这里打开确认页</a>'));
    render();
    refresh(true);
  });

  // ---------- polling ----------
  function start() {
    if (timer) return;
    render(); refresh(true);
    timer = setInterval(function () { if (!document.hidden) refresh(false); }, POLL_MS);
    document.addEventListener('visibilitychange', function () { if (!document.hidden) refresh(true); });
    window.addEventListener('focus', function () { refresh(false); });
    window.addEventListener('pageshow', function () { refresh(true); });
  }
})();

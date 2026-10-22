part of 'server.dart';

/// Web de la tele: un único HTML sin dependencias, pensado para navegadores
/// de TV poco potentes (Silk en modo móvil). Se controla desde el móvil
/// (modo mando) o con las flechas del mando de la tele.
const tvPageHtml = r'''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>KofuReader · Tele</title>
<style>
  :root { --accent:#ff5d8f; --accent2:#8c6bff; --muted:#9393a8; }
  * { box-sizing:border-box; margin:0; padding:0; }
  html, body { width:100%; height:100%; background:#000; color:#f2f2f7; overflow:hidden;
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  .screen { position:fixed; inset:0; display:none; }
  .screen.on { display:flex; }
  #wait { flex-direction:column; align-items:center; justify-content:center; text-align:center; gap:2.5vh;
    background: radial-gradient(circle at 50% 35%, #2a1640 0%, #0c0c11 60%); }
  .logo { font-size:7vh; font-weight:800; letter-spacing:-.02em;
    background:linear-gradient(135deg,var(--accent),var(--accent2)); -webkit-background-clip:text; background-clip:text; color:transparent; }
  .hint { color:var(--muted); font-size:3vh; max-width:70vw; line-height:1.4; }
  .code { font-size:16vh; font-weight:800; letter-spacing:.15em; padding:1vh 4vh; border-radius:3vh;
    background:rgba(255,255,255,.06); border:.3vh solid rgba(255,93,143,.5); }
  .small { color:var(--muted); font-size:2.2vh; }
  #paged { align-items:center; justify-content:center; }
  #paged img { height:100vh; max-width:100vw; object-fit:contain; display:block; }
  #paged.two img { max-width:50vw; }
  #vertical { display:none; overflow-y:auto; justify-content:center; }
  #vertical.on { display:block; }
  #vcol { width:min(100vw, 56vh); margin:0 auto; }
  #vcol img { width:100%; display:block; min-height:20vh; background:#111; }
  #end { flex-direction:column; align-items:center; justify-content:center; text-align:center; gap:2vh; }
  #end .t { font-size:4.5vh; font-weight:800; max-width:80vw; }
  .check { width:10vh; height:10vh; border-radius:50%; display:flex; align-items:center; justify-content:center;
    background:linear-gradient(135deg,var(--accent),var(--accent2)); font-size:6vh; }
  #info { position:fixed; left:0; right:0; bottom:0; padding:3vh 4vw; display:flex; justify-content:space-between; align-items:flex-end;
    background:linear-gradient(transparent, rgba(0,0,0,.85)); font-size:2.8vh; opacity:0; transition:opacity .3s; pointer-events:none; }
  #info.show { opacity:1; }
  #info .ttl { font-weight:700; max-width:70vw; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  #status { position:fixed; top:2vh; right:2vw; font-size:2vh; color:var(--muted); }
</style>
</head>
<body>
  <div id="wait" class="screen on">
    <div class="logo">KofuReader</div>
    <div id="waitMsg" class="hint">Conectando…</div>
    <div id="code" class="code" style="display:none"></div>
    <div id="waitSmall" class="small"></div>
  </div>
  <div id="paged" class="screen"></div>
  <div id="vertical" class="screen"><div id="vcol"></div></div>
  <div id="end" class="screen">
    <div class="check">✓</div>
    <div class="small">CAPÍTULO TERMINADO</div>
    <div id="endTitle" class="t"></div>
    <div class="small">Elige el siguiente desde el móvil</div>
  </div>
  <div id="info"><div class="ttl" id="infoTitle"></div><div id="infoPage"></div></div>
  <div id="status"></div>
<script>
(function () {
  var $ = function (id) { return document.getElementById(id); };
  function rid() { var s = ''; for (var i = 0; i < 24; i++) s += 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]; return s; }
  var store = { get: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
                set: function (k, v) { try { localStorage.setItem(k, v); } catch (e) {} } };
  var tvId = store.get('kofu_tv_id'); if (!tvId) { tvId = rid(); store.set('kofu_tv_id', tvId); }
  var secret = store.get('kofu_tv_secret');
  var ws = null, book = null, views = [], view = 0, infoTimer = null;

  function show(id) {
    ['wait', 'paged', 'vertical', 'end'].forEach(function (s) { $(s).classList.toggle('on', s === id); });
  }
  function send(o) { if (ws && ws.readyState === 1) ws.send(JSON.stringify(o)); }

  function connect() {
    var proto = location.protocol === 'https:' ? 'wss' : 'ws';
    ws = new WebSocket(proto + '://' + location.host + '/tvws?id=' + tvId + (secret ? '&s=' + secret : ''));
    ws.onmessage = function (e) { var m; try { m = JSON.parse(e.data); } catch (x) { return; } onMessage(m); };
    ws.onclose = function () { $('status').textContent = 'Reconectando…'; setTimeout(connect, 3000); };
    ws.onopen = function () { $('status').textContent = ''; };
  }

  function waiting() {
    book = null;
    $('code').style.display = 'none';
    $('waitMsg').textContent = 'Lista. Elige qué leer desde el móvil.';
    $('waitSmall').textContent = 'Modo mando → Tele → Elegir qué leer';
    show('wait');
  }

  function onMessage(m) {
    if (m.type === 'code') {
      $('waitMsg').textContent = 'En el móvil: Modo mando → Añadir tele, y escribe:';
      $('code').textContent = m.code; $('code').style.display = '';
      $('waitSmall').textContent = 'Solo hace falta la primera vez';
      show('wait');
    } else if (m.type === 'paired') {
      secret = m.secret; store.set('kofu_tv_secret', secret);
    } else if (m.type === 'ready') {
      if (!book) waiting(); else publish();
    } else if (m.type === 'command') {
      command(m);
    }
  }

  // ---- Libro ----

  function pageUrl(n) { return '/tv/page?id=' + tvId + '&s=' + secret + '&b=' + book.bookId + '&n=' + n; }

  function buildViews(pages, spreads) {
    var v = [], i = 0;
    function wide(k) { var p = pages[k]; return p.w && p.h && p.w > p.h; }
    if (!spreads) { for (i = 0; i < pages.length; i++) v.push([i]); return v; }
    while (i < pages.length) {
      if (i === 0 || wide(i) || i + 1 >= pages.length || wide(i + 1)) { v.push([i]); i++; }
      else { v.push([i, i + 1]); i += 2; }
    }
    return v;
  }
  function viewOf(pageIndex) {
    for (var i = 0; i < views.length; i++) if (views[i].indexOf(pageIndex) >= 0) return i;
    return 0;
  }

  function open(m) {
    book = m;
    var landscape = window.innerWidth > window.innerHeight;
    views = buildViews(m.pages, m.mode !== 'vertical' && m.spreads !== false && landscape);
    if (m.mode === 'vertical') {
      var col = $('vcol'); col.innerHTML = '';
      m.pages.forEach(function (p) {
        var img = document.createElement('img');
        img.loading = 'lazy'; img.src = pageUrl(p.n);
        if (p.w && p.h) img.style.aspectRatio = p.w + ' / ' + p.h;
        col.appendChild(img);
      });
      show('vertical');
      var start = Math.max(0, (m.startPage || 1) - 1);
      setTimeout(function () { var el = col.children[start]; if (el) $('vertical').scrollTop = el.offsetTop; }, 50);
    } else {
      view = viewOf(Math.max(0, (m.startPage || 1) - 1));
      renderPaged();
    }
    flashInfo();
    publish();
  }

  function renderPaged() {
    if (view >= views.length) { $('endTitle').textContent = book.title || ''; show('end'); publish(); return; }
    var box = $('paged'); box.innerHTML = '';
    var idx = views[view].slice();
    if (book.mode === 'pagedRtl') idx.reverse(); // manga: la primera página del par a la derecha
    box.classList.toggle('two', idx.length === 2);
    idx.forEach(function (i) { var img = document.createElement('img'); img.src = pageUrl(book.pages[i].n); box.appendChild(img); });
    show('paged');
    // Precarga de las siguientes vistas.
    for (var k = view + 1; k <= view + 4 && k < views.length; k++) {
      views[k].forEach(function (i) { var im = new Image(); im.src = pageUrl(book.pages[i].n); });
    }
    publish();
  }

  function currentPage() {
    if (!book) return 0;
    if (book.mode === 'vertical') {
      var v = $('vertical'), mid = v.scrollTop + v.clientHeight / 2, imgs = $('vcol').children, p = 1;
      for (var i = 0; i < imgs.length; i++) if (imgs[i].offsetTop <= mid) p = i + 1;
      return p;
    }
    if (view >= views.length) return book.pages.length;
    var vv = views[view]; return vv[vv.length - 1] + 1;
  }
  function atEnd() {
    if (!book) return false;
    if (book.mode === 'vertical') { var v = $('vertical'); return v.scrollTop + v.clientHeight >= v.scrollHeight - 4; }
    return view >= views.length;
  }

  function publish() {
    if (!book) { send({ type: 'state', state: {} }); return; }
    send({ type: 'state', state: { bookId: book.bookId, title: book.title || '', series: book.series || '',
      page: currentPage(), total: book.pages.length, mode: book.mode, atEnd: atEnd() } });
    $('infoTitle').textContent = (book.series ? book.series + ' · ' : '') + (book.title || '');
    $('infoPage').textContent = currentPage() + ' / ' + book.pages.length;
  }

  function flashInfo() {
    $('info').classList.add('show'); clearTimeout(infoTimer);
    infoTimer = setTimeout(function () { $('info').classList.remove('show'); }, 3000);
  }

  function next() {
    if (!book) return;
    if (book.mode === 'vertical') return scrollBy(0.85, true);
    if (view < views.length) { view++; renderPaged(); }
  }
  function prev() {
    if (!book) return;
    if (book.mode === 'vertical') return scrollBy(-0.85, true);
    if (view > 0) { view--; renderPaged(); }
  }
  function scrollBy(fraction, smooth) {
    var v = $('vertical');
    if (smooth && v.scrollBy) v.scrollBy({ top: fraction * v.clientHeight, behavior: 'smooth' });
    else v.scrollTop += fraction * v.clientHeight;
  }

  var pubTimer = null;
  $('vertical').addEventListener('scroll', function () { clearTimeout(pubTimer); pubTimer = setTimeout(publish, 150); });

  function command(m) {
    switch (m.cmd) {
      case 'open': open(m); break;
      case 'next': next(); break;
      case 'prev': prev(); break;
      case 'scroll': if (book && book.mode === 'vertical') scrollBy(+m.dy || 0, false); break;
      case 'fling': if (book && book.mode === 'vertical') scrollBy((+m.v || 0) * 0.35, true); break;
      case 'overlay': flashInfo(); break;
      case 'exit': waiting(); publish(); break;
    }
  }

  // ---- Mando de la tele ----

  function fullscreen() {
    var d = document.documentElement;
    if (!document.fullscreenElement && d.requestFullscreen) d.requestFullscreen().catch(function () {});
  }
  document.addEventListener('click', fullscreen);
  document.addEventListener('keydown', function (e) {
    fullscreen();
    var rtl = book && book.mode === 'pagedRtl';
    switch (e.key) {
      case 'ArrowRight': rtl ? prev() : next(); break;
      case 'ArrowLeft': rtl ? next() : prev(); break;
      case 'ArrowDown': book && book.mode === 'vertical' ? scrollBy(0.3, true) : next(); break;
      case 'ArrowUp': book && book.mode === 'vertical' ? scrollBy(-0.3, true) : prev(); break;
      case 'Enter': flashInfo(); break;
      default: return;
    }
    e.preventDefault();
  });

  connect();
})();
</script>
</body>
</html>
''';

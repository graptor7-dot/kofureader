part of 'server.dart';

// ---------------------------------------------------------------------------
// Modo tele: una web ligera en /tv para el navegador de la tele.
//
// - La tele abre /tv y se conecta por WebSocket a /tvws (sin token).
// - Si no está emparejada, recibe un código de 4 cifras; el móvil lo envía
//   ({type: pair, code}) y la tele recibe un secreto que guarda en su navegador.
// - Emparejada, aparece como una pantalla más del modo mando (kind: tv).
// - Para abrir un libro, el móvil manda {cmd: open} con la URL de Komga y su
//   cabecera de autenticación; el servidor las guarda solo en memoria y sirve
//   las páginas a la tele en /tv/page (la tele nunca habla con Komga).
// ---------------------------------------------------------------------------

late final File _tvFile;

/// tvId -> secreto de emparejamiento (persistente).
final Map<String, String> _tvSecrets = {};

/// tvId -> libro abierto: {baseUrl, headers, bookId} (solo en memoria).
final Map<String, Map<String, dynamic>> _tvBooks = {};

/// Código de emparejamiento -> tele que lo muestra.
final Map<String, _Peer> _tvCodes = {};

final _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

Future<void> _loadTv(Directory dataDir) async {
  _tvFile = File('${dataDir.path}/tv.json');
  if (!await _tvFile.exists()) return;
  try {
    (jsonDecode(await _tvFile.readAsString()) as Map).forEach((k, v) => _tvSecrets['$k'] = '$v');
  } catch (_) {}
}

Future<void> _saveTv() => _tvFile.writeAsString(jsonEncode(_tvSecrets), flush: true);

String _randomSecret() {
  final r = Random.secure();
  return List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

String _newCode() {
  final r = Random.secure();
  String code;
  do {
    code = (1000 + r.nextInt(9000)).toString();
  } while (_tvCodes.containsKey(code));
  return code;
}

bool _tvAuthorized(String id, String? secret) {
  final expected = _tvSecrets[id];
  if (expected == null || secret == null || secret.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < secret.length; i++) {
    diff |= secret.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}

/// WebSocket de la tele.
void _tvSocket(WebSocket socket, String id, String? secret) {
  socket.pingInterval = const Duration(seconds: 20);
  final peer = _Peer(socket)
    ..deviceId = id
    ..name = 'Tele'
    ..kind = 'tv';
  _peers.add(peer);

  if (_tvAuthorized(id, secret)) {
    _becomeScreen(peer);
  } else {
    final code = _newCode();
    peer.pairCode = code;
    _tvCodes[code] = peer;
    socket.add(jsonEncode({'type': 'code', 'code': code}));
  }

  socket.listen(
    (data) {
      try {
        final msg = (jsonDecode(data as String) as Map).cast<String, dynamic>();
        if (msg['type'] == 'state' && peer.role == 'screen') {
          peer.state = (msg['state'] as Map? ?? {}).cast<String, dynamic>();
          _broadcastScreens();
        }
      } catch (_) {}
    },
    onDone: () {
      _peers.remove(peer);
      if (peer.pairCode != null) _tvCodes.remove(peer.pairCode);
      if (peer.role == 'screen') _broadcastScreens();
    },
    onError: (_) {},
    cancelOnError: true,
  );
}

void _becomeScreen(_Peer tv) {
  // Una tele reconectada sustituye a su conexión anterior.
  for (final old in _peers.where((p) => p != tv && p.deviceId == tv.deviceId && p.role == 'screen').toList()) {
    _peers.remove(old);
    old.socket.close();
  }
  tv.role = 'screen';
  tv.socket.add(jsonEncode({'type': 'ready'}));
  _broadcastScreens();
}

/// El móvil escribe el código que muestra la tele.
Future<void> _pairTv(_Peer remote, String code) async {
  final tv = _tvCodes.remove(code);
  if (tv == null) {
    remote.socket.add(jsonEncode({'type': 'paired', 'ok': false}));
    return;
  }
  tv.pairCode = null;
  final secret = _randomSecret();
  _tvSecrets[tv.deviceId] = secret;
  await _saveTv();
  tv.socket.add(jsonEncode({'type': 'paired', 'secret': secret}));
  _becomeScreen(tv);
  remote.socket.add(jsonEncode({'type': 'paired', 'ok': true, 'deviceId': tv.deviceId}));
}

/// Orden "open" para una tele: se guarda cómo llegar a Komga y se reenvía sin credenciales.
void _openOnTv(_Peer tv, Map<String, dynamic> msg) {
  _tvBooks[tv.deviceId] = {
    'baseUrl': msg['baseUrl'],
    'headers': (msg['headers'] as Map? ?? {}).cast<String, dynamic>(),
    'bookId': msg['bookId'],
  };
  final safe = Map<String, dynamic>.of(msg)
    ..remove('baseUrl')
    ..remove('headers');
  tv.socket.add(jsonEncode(safe));
}

/// GET /tv/page?id=&s=&n= : página n del libro abierto en esa tele.
Future<void> _tvPage(HttpRequest req) async {
  final q = req.uri.queryParameters;
  final id = q['id'] ?? '';
  if (!_tvAuthorized(id, q['s'])) return _json(req, 401, {'error': 'unauthorized'});
  final book = _tvBooks[id];
  final n = int.tryParse(q['n'] ?? '');
  if (book == null || n == null || q['b'] != book['bookId']) return _json(req, 404, {'error': 'no book'});
  try {
    final base = '${book['baseUrl']}'.replaceAll(RegExp(r'/+$'), '');
    final upstream = await _http.getUrl(Uri.parse('$base/api/v1/books/${book['bookId']}/pages/$n'));
    (book['headers'] as Map<String, dynamic>).forEach((k, v) => upstream.headers.set(k, '$v'));
    final res = await upstream.close().timeout(const Duration(seconds: 30));
    req.response.statusCode = res.statusCode;
    final type = res.headers.contentType;
    if (type != null) req.response.headers.contentType = type;
    req.response.headers.set('Cache-Control', 'private, max-age=3600');
    await res.pipe(req.response);
  } catch (e) {
    try {
      _json(req, 502, {'error': 'komga'});
    } catch (_) {}
  }
}

void _tvHtml(HttpRequest req) {
  req.response
    ..statusCode = 200
    ..headers.contentType = ContentType.html
    ..headers.set('Cache-Control', 'no-cache')
    ..write(tvPageHtml);
  req.response.close();
}

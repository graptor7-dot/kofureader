// KofuSync: servicio mínimo de sincronización para KofuReader.
//
// Guarda registros (listas, elementos, preferencias, servidores) en un
// fichero JSON. Cada registro tiene `updatedAt` y gana el más reciente.
// Cada cambio aceptado recibe un número de secuencia (`seq`) para que los
// clientes pidan solo lo nuevo desde su último cursor.
//
// Variables de entorno:
//   KOFUSYNC_TOKEN  (obligatoria) token que deben enviar los clientes
//   KOFUSYNC_DATA   carpeta de datos (por defecto /data)
//   KOFUSYNC_PORT   puerto (por defecto 8080)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _maxBody = 20 * 1024 * 1024;

late final String _token;
late final File _file;
final Map<String, Map<String, dynamic>> _records = {};
int _seq = 0;
Future<void> _writing = Future.value();

Future<void> main() async {
  final env = Platform.environment;
  final token = env['KOFUSYNC_TOKEN'] ?? '';
  if (token.length < 16) {
    stderr.writeln('KOFUSYNC_TOKEN es obligatorio y debe tener al menos 16 caracteres.');
    exit(1);
  }
  _token = token;
  final dataDir = Directory(env['KOFUSYNC_DATA'] ?? '/data');
  await dataDir.create(recursive: true);
  _file = File('${dataDir.path}/kofusync.json');
  await _load();

  final port = int.tryParse(env['KOFUSYNC_PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('KofuSync escuchando en el puerto $port (${_records.length} registros, seq $_seq)');
  ProcessSignal.sigint.watch().listen((_) => _shutdown(server));
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen((_) => _shutdown(server));

  await for (final req in server) {
    unawaited(_handle(req));
  }
}

Future<void> _shutdown(HttpServer server) async {
  await server.close();
  await _writing;
  exit(0);
}

Future<void> _load() async {
  if (!await _file.exists()) return;
  final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
  _seq = json['seq'] as int? ?? 0;
  for (final r in (json['records'] as List? ?? [])) {
    final rec = (r as Map).cast<String, dynamic>();
    _records[_key(rec)] = rec;
  }
}

/// Escritura atómica (fichero temporal + renombrado), encadenada para no solapar.
Future<void> _save() {
  final snapshot = jsonEncode({'version': 1, 'seq': _seq, 'records': _records.values.toList()});
  return _writing = _writing.then((_) async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(snapshot, flush: true);
    await tmp.rename(_file.path);
  });
}

String _key(Map<String, dynamic> r) => '${r['type']}:${r['id']}';

bool _authorized(HttpRequest req) {
  final header = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
  const prefix = 'Bearer ';
  if (!header.startsWith(prefix)) return false;
  final given = header.substring(prefix.length);
  // Comparación en tiempo constante.
  if (given.length != _token.length) return false;
  var diff = 0;
  for (var i = 0; i < given.length; i++) {
    diff |= given.codeUnitAt(i) ^ _token.codeUnitAt(i);
  }
  return diff == 0;
}

Future<void> _handle(HttpRequest req) async {
  try {
    final path = req.uri.path;
    if (req.method == 'GET' && path == '/health') {
      return _json(req, 200, {'ok': true, 'version': 2, 'remote': true});
    }
    if (path == '/remote' && WebSocketTransformer.isUpgradeRequest(req)) {
      if (!_authorized(req)) return _json(req, 401, {'error': 'unauthorized'});
      final socket = await WebSocketTransformer.upgrade(req);
      return _remote(socket);
    }
    if (req.method == 'POST' && path == '/sync') {
      if (!_authorized(req)) return _json(req, 401, {'error': 'unauthorized'});
      return await _sync(req);
    }
    return _json(req, 404, {'error': 'not found'});
  } catch (e) {
    stderr.writeln('Error en ${req.method} ${req.uri}: $e');
    try {
      _json(req, 400, {'error': 'bad request'});
    } catch (_) {}
  }
}

/// POST /sync  {since: int, changes: [registro]}
/// -> {cursor: int, changes: [registros con seq > since]}
Future<void> _sync(HttpRequest req) async {
  final bytes = <int>[];
  await for (final chunk in req) {
    bytes.addAll(chunk);
    if (bytes.length > _maxBody) return _json(req, 413, {'error': 'too large'});
  }
  final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final since = body['since'] as int? ?? 0;
  var accepted = 0;
  for (final c in (body['changes'] as List? ?? [])) {
    final rec = (c as Map).cast<String, dynamic>();
    if (rec['type'] is! String || rec['id'] is! String || rec['updatedAt'] is! int) continue;
    final key = _key(rec);
    final existing = _records[key];
    if (existing != null && (existing['updatedAt'] as int) >= (rec['updatedAt'] as int)) continue;
    _records[key] = {
      'type': rec['type'],
      'id': rec['id'],
      'updatedAt': rec['updatedAt'],
      'deleted': rec['deleted'] == true,
      'data': rec['data'],
      'seq': ++_seq,
    };
    accepted++;
  }
  if (accepted > 0) await _save();
  final changes = _records.values.where((r) => (r['seq'] as int) > since).toList();
  _json(req, 200, {'cursor': _seq, 'accepted': accepted, 'changes': changes});
}

void _json(HttpRequest req, int status, Object body) {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  req.response.close();
}

// ---------------------------------------------------------------------------
// Modo mando: el móvil controla el lector de otro dispositivo.
//
// Cada dispositivo abre un WebSocket en /remote y se presenta:
//   {type: hello, deviceId, name, role: screen|remote}
// Las pantallas (lector abierto) envían su estado: {type: state, ...}
// Los mandos reciben la lista: {type: screens, screens: [{deviceId, name, ...estado}]}
// y envían órdenes: {type: command, to, cmd, ...} o {type: attach, to}
// que se reenvían a esa pantalla tal cual (con "from").
// ---------------------------------------------------------------------------

class _Peer {
  final WebSocket socket;
  String deviceId = '';
  String name = '';
  String role = '';
  Map<String, dynamic> state = {};

  _Peer(this.socket);
}

final _peers = <_Peer>{};

void _remote(WebSocket socket) {
  socket.pingInterval = const Duration(seconds: 20);
  final peer = _Peer(socket);
  _peers.add(peer);
  socket.listen(
    (data) {
      try {
        final msg = (jsonDecode(data as String) as Map).cast<String, dynamic>();
        _onRemoteMessage(peer, msg);
      } catch (_) {}
    },
    onDone: () {
      _peers.remove(peer);
      if (peer.role == 'screen') _broadcastScreens();
    },
    onError: (_) {},
    cancelOnError: true,
  );
}

void _onRemoteMessage(_Peer peer, Map<String, dynamic> msg) {
  switch (msg['type']) {
    case 'hello':
      peer
        ..deviceId = '${msg['deviceId']}'
        ..name = '${msg['name']}'
        ..role = '${msg['role']}';
      // Un dispositivo reconectado sustituye a su conexión anterior con el mismo papel.
      for (final old in _peers.where((p) => p != peer && p.deviceId == peer.deviceId && p.role == peer.role).toList()) {
        _peers.remove(old);
        old.socket.close();
      }
      if (peer.role == 'remote') {
        _sendScreens(peer);
      } else {
        _broadcastScreens();
      }
    case 'state' when peer.role == 'screen':
      peer.state = (msg['state'] as Map? ?? {}).cast<String, dynamic>();
      _broadcastScreens();
    case 'command' || 'attach' when peer.role == 'remote':
      final target = _peers.where((p) => p.role == 'screen' && p.deviceId == msg['to']).firstOrNull;
      target?.socket.add(jsonEncode({...msg, 'from': peer.deviceId, 'fromName': peer.name}));
  }
}

List<Map<String, dynamic>> _screenList() => [
  for (final p in _peers)
    if (p.role == 'screen') {'deviceId': p.deviceId, 'name': p.name, ...p.state},
];

void _sendScreens(_Peer remote) => remote.socket.add(jsonEncode({'type': 'screens', 'screens': _screenList()}));

void _broadcastScreens() {
  for (final p in _peers.where((p) => p.role == 'remote').toList()) {
    _sendScreens(p);
  }
}
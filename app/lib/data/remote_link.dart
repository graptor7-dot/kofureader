import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'app_state.dart';

enum RemoteRole { screen, remote }

/// Nombre con el que este dispositivo aparece en el modo mando.
String deviceName() {
  if (Platform.isWindows) return 'PC';
  if (Platform.isIOS) return 'iPad';
  if (Platform.isAndroid) return 'Móvil';
  return 'Dispositivo';
}

/// Identificador estable de este dispositivo (no se sincroniza).
String deviceId(AppState state) {
  final existing = state.data.localPref('device_id');
  if (existing != null) return existing;
  final id = const Uuid().v4();
  state.data.setLocalPref('device_id', id);
  return id;
}

/// Conexión del modo mando con KofuSync (WebSocket en /remote).
///
/// Se reconecta sola si se corta. Una pantalla (lector abierto) usa
/// [RemoteRole.screen]; el móvil que hace de mando, [RemoteRole.remote].
class RemoteLink extends ChangeNotifier {
  final AppState state;
  final RemoteRole role;
  final void Function(Map<String, dynamic> message) onMessage;

  WebSocket? _socket;
  bool _closed = false;
  bool connected = false;
  String? error;
  Timer? _retry;
  Map<String, dynamic>? _lastState;

  RemoteLink(this.state, this.role, {required this.onMessage});

  /// Null si KofuSync no está configurado (sin él no hay modo mando).
  static RemoteLink? create(AppState state, RemoteRole role, {required void Function(Map<String, dynamic>) onMessage}) {
    if (!state.sync.configured) return null;
    return RemoteLink(state, role, onMessage: onMessage)..connect();
  }

  Uri get _uri {
    final base = Uri.parse(state.sync.url!);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '${base.path}/remote');
  }

  Future<void> connect() async {
    if (_closed) return;
    try {
      final socket = await WebSocket.connect(
        _uri.toString(),
        headers: {'Authorization': 'Bearer ${state.sync.token}'},
      ).timeout(const Duration(seconds: 10));
      if (_closed) {
        await socket.close();
        return;
      }
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      connected = true;
      error = null;
      notifyListeners();
      _send({'type': 'hello', 'deviceId': deviceId(state), 'name': deviceName(), 'role': role.name});
      if (_lastState != null) _send({'type': 'state', 'state': _lastState});
      socket.listen(
        (data) {
          try {
            onMessage((jsonDecode(data as String) as Map).cast<String, dynamic>());
          } catch (_) {}
        },
        onDone: _onLost,
        onError: (_) => _onLost(),
        cancelOnError: true,
      );
    } catch (e) {
      error = e is WebSocketException && e.message.contains('404')
          ? 'Actualiza KofuSync en el servidor para usar el modo mando'
          : 'Sin conexión con KofuSync';
      _onLost();
    }
  }

  void _onLost() {
    _socket = null;
    if (connected) {
      connected = false;
      notifyListeners();
    } else {
      notifyListeners();
    }
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), connect);
  }

  void _send(Map<String, dynamic> msg) {
    final socket = _socket;
    if (socket != null && socket.readyState == WebSocket.open) socket.add(jsonEncode(msg));
  }

  /// Pantalla: publica qué se está leyendo (título, página…).
  void publishState(Map<String, dynamic> s) {
    _lastState = s;
    _send({'type': 'state', 'state': s});
  }

  /// Mando: avisa a la pantalla de que se ha conectado.
  void attach(String to) => _send({'type': 'attach', 'to': to});

  /// Mando: envía una orden a la pantalla [to].
  void command(String to, String cmd, [Map<String, dynamic> args = const {}]) =>
      _send({'type': 'command', 'to': to, 'cmd': cmd, ...args});

  void close() {
    _closed = true;
    _retry?.cancel();
    _socket?.close();
    _socket = null;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}

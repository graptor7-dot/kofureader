import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'source.dart';
import 'user_data.dart';

class SyncException implements Exception {
  final String message;

  SyncException(this.message);

  @override
  String toString() => message;
}

class _Retry implements Exception {}

/// Sincroniza [UserData] con un servidor KofuSync.
///
/// Envía los registros cambiados desde la última subida y recibe los que
/// han cambiado en el servidor desde el último cursor. Se lanza al abrir la
/// app, al volver a ella, poco después de cada cambio y cada pocos minutos.
class SyncService extends ChangeNotifier {
  static const _tokenKey = 'kofusync:token';
  static const _storage = FlutterSecureStorage();
  static const _timeout = Duration(seconds: 20);

  final UserData data;
  String _token = '';
  bool _syncing = false;
  bool _again = false;
  String? lastError;
  Timer? _debounce;
  Timer? _periodic;
  AppLifecycleListener? _lifecycle;

  SyncService(this.data);

  String? get url => data.syncMeta['url'] as String?;
  bool get configured => url != null && _token.isNotEmpty;
  bool get syncing => _syncing;
  DateTime? get lastSync {
    final ms = data.syncMeta['lastSync'] as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> init() async {
    _token = await _storage.read(key: _tokenKey) ?? '';
    data.addListener(_onDataChanged);
    _lifecycle = AppLifecycleListener(onResume: () => syncNow());
    _periodic = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    if (configured) unawaited(syncNow());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    _lifecycle?.dispose();
    data.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (data.applyingRemote || !configured) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  /// Comprueba el servidor y guarda la configuración. Lanza [SyncException] si falla.
  Future<void> configure(String rawUrl, String token) async {
    final newUrl = Source.normalizeUrl(rawUrl);
    await _check(newUrl, token);
    if (newUrl != url) {
      // Servidor nuevo: subir todo y pedir todo.
      data.syncMeta
        ..['cursor'] = 0
        ..['lastPushAt'] = 0;
    }
    data.syncMeta['url'] = newUrl;
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
    data.saveSoon();
    notifyListeners();
    await syncNow();
  }

  Future<void> disable() async {
    data.syncMeta
      ..remove('url')
      ..remove('cursor')
      ..remove('lastPushAt')
      ..remove('lastSync');
    _token = '';
    lastError = null;
    await _storage.delete(key: _tokenKey);
    data.saveSoon();
    notifyListeners();
  }

  Future<void> _check(String url, String token) async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$url/sync'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode({'since': 1 << 40, 'changes': []}),
          )
          .timeout(_timeout);
    } catch (e) {
      throw SyncException('No se puede conectar con KofuSync ($e)');
    }
    if (res.statusCode == 401) throw SyncException('Token incorrecto');
    if (res.statusCode != 200) throw SyncException('KofuSync respondió ${res.statusCode}');
  }

  /// Sincroniza ahora. Devuelve true si ha ido bien.
  Future<bool> syncNow() async {
    if (!configured) return false;
    if (_syncing) {
      _again = true; // hubo cambios durante la sincronización: repetir al acabar
      return true;
    }
    _syncing = true;
    notifyListeners();
    var ok = false;
    try {
      final started = DateTime.now().millisecondsSinceEpoch;
      final lastPushAt = data.syncMeta['lastPushAt'] as int? ?? 0;
      final cursor = data.syncMeta['cursor'] as int? ?? 0;
      final changes = data.changesSince(lastPushAt);
      final http.Response res;
      try {
        res = await http
            .post(
              Uri.parse('$url/sync'),
              headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
              body: jsonEncode({'since': cursor, 'changes': changes}),
            )
            .timeout(_timeout);
      } catch (_) {
        throw SyncException('Sin conexión con KofuSync');
      }
      if (res.statusCode == 401) throw SyncException('Token incorrecto');
      if (res.statusCode != 200) throw SyncException('KofuSync respondió ${res.statusCode}');
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if ((body['cursor'] as int) < cursor) {
        // El servidor se ha reiniciado desde cero: volver a subirlo todo.
        data.syncMeta
          ..['cursor'] = 0
          ..['lastPushAt'] = 0;
        throw _Retry();
      }
      data.applyRemote(body['changes'] as List);
      data.syncMeta
        ..['cursor'] = body['cursor'] as int
        ..['lastPushAt'] = started
        ..['lastSync'] = DateTime.now().millisecondsSinceEpoch;
      data.saveSoon();
      lastError = null;
      ok = true;
      // Cambios hechos durante la sincronización (o al fusionar servidores): subirlos ya.
      if (data.changesSince(started).isNotEmpty) _again = true;
    } on _Retry {
      _again = true;
    } on SyncException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = 'Error de sincronización: $e';
    } finally {
      _syncing = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      return syncNow();
    }
    return ok;
  }
}

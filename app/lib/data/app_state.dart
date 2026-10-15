import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../komga/komga_client.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'downloads.dart';
import 'source.dart';
import 'sync_service.dart';
import 'user_data.dart';

enum ReadingMode {
  pagedRtl('Páginas (derecha → izquierda)'),
  pagedLtr('Páginas (izquierda → derecha)'),
  vertical('Scroll vertical');

  final String label;
  const ReadingMode(this.label);
}

/// Una biblioteca junto con el servidor del que viene.
class LibraryEntry {
  final Source source;
  final KomgaLibrary library;

  LibraryEntry(this.source, this.library);

  String get key => '${source.id}|${library.id}';
}

/// Resultado de cargar las bibliotecas de un servidor.
class SourceLibraries {
  final Source source;
  final List<LibraryEntry> libraries;
  final String? error;
  final bool needsSecret;

  SourceLibraries(this.source, this.libraries, [this.error, this.needsSecret = false]);
}

/// Un libro junto con su servidor.
class SourcedBook {
  final Source source;
  final KomgaBook book;

  SourcedBook(this.source, this.book);
}

/// Estado global: servidores configurados, sus clientes y datos del usuario.
class AppState extends ChangeNotifier {
  static const _sourcesKey = 'sources';
  static const _secureStorage = FlutterSecureStorage();

  final UserData data = UserData();
  late final SyncService sync = SyncService(data);

  /// Secretos (API key o contraseña) de cada servidor; solo en este dispositivo.
  final Map<String, String> _secrets = {};
  final Map<String, KomgaClient> _clients = {};
  String _sourcesSignature = '';

  /// Servidores, sincronizados entre dispositivos (sin credenciales).
  List<Source> get sources => data.sources;

  Future<void> init() async {
    await data.init();
    await _migrateLegacySources();
    for (final s in data.sources) {
      _secrets[s.id] = await _secureStorage.read(key: _secretKey(s.id)) ?? '';
    }
    _sourcesSignature = _signature();
    data.onSourceRemapped = _moveSecret;
    data.addListener(_onDataChanged);
    sync.addListener(notifyListeners);
    await sync.init();
    await downloads.init();
    downloads.addListener(notifyListeners);
    // Progreso leído sin conexión: enviarlo en cuanto se pueda.
    unawaited(flushPendingProgress());
    _pendingTimer = Timer.periodic(const Duration(minutes: 2), (_) => flushPendingProgress());
    _lifecycle = AppLifecycleListener(onResume: flushPendingProgress);
  }

  final DownloadManager downloads = DownloadManager();
  Timer? _pendingTimer;
  AppLifecycleListener? _lifecycle;

  Future<void> flushPendingProgress() =>
      downloads.flushPendingProgress((id) => source(id) != null && hasSecret(id) ? client(id) : null);

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Versiones anteriores guardaban los servidores en SharedPreferences.
  Future<void> _migrateLegacySources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sourcesKey);
    if (raw == null) return;
    if (!data.hasAnySourceRecord) {
      for (final j in jsonDecode(raw) as List) {
        data.upsertSource(Source.fromJson(j as Map<String, dynamic>));
      }
    }
    await prefs.remove(_sourcesKey);
  }

  String _signature() => data.sources.map((s) => '${s.id}${s.baseUrl}${s.authType}${s.username}').join('|');

  void _onDataChanged() {
    final sig = _signature();
    if (sig != _sourcesSignature) {
      // Cambió algún servidor (local o por sincronización): rehacer clientes.
      _sourcesSignature = sig;
      for (final c in _clients.values) {
        c.close();
      }
      _clients.clear();
      _libraryCache = null;
    }
    notifyListeners();
  }

  Future<void> _moveSecret(String oldId, String newId) async {
    final secret = _secrets.remove(oldId);
    if (secret == null || secret.isEmpty) return;
    if ((_secrets[newId] ?? '').isEmpty) {
      _secrets[newId] = secret;
      await _secureStorage.write(key: _secretKey(newId), value: secret);
    }
    await _secureStorage.delete(key: _secretKey(oldId));
    _clients.remove(newId)?.close();
    notifyListeners();
  }

  String _secretKey(String sourceId) => 'secret:$sourceId';

  /// False si el servidor llegó por sincronización y aún falta su API key aquí.
  bool hasSecret(String sourceId) => (_secrets[sourceId] ?? '').isNotEmpty;

  KomgaClient client(String sourceId) =>
      _clients.putIfAbsent(sourceId, () => KomgaClient(source(sourceId)!, _secrets[sourceId] ?? ''));

  Source? source(String sourceId) {
    for (final s in data.sources) {
      if (s.id == sourceId) return s;
    }
    return null;
  }

  Color sourceColor(String sourceId) {
    final i = data.sources.indexWhere((s) => s.id == sourceId);
    return Kofu.sourceColors[(i < 0 ? 0 : i) % Kofu.sourceColors.length];
  }

  /// Añade o actualiza un servidor. [secret] nulo = mantener el actual.
  Future<void> saveSource(Source source, String? secret) async {
    if (secret != null) {
      _secrets[source.id] = secret;
      await _secureStorage.write(key: _secretKey(source.id), value: secret);
    }
    _clients.remove(source.id)?.close();
    _libraryCache = null;
    data.upsertSource(source);
  }

  Future<void> removeSource(String sourceId) async {
    _secrets.remove(sourceId);
    await _secureStorage.delete(key: _secretKey(sourceId));
    data.deleteSource(sourceId);
  }

  // ---- Bibliotecas ----

  List<SourceLibraries>? _libraryCache;

  /// Bibliotecas de todos los servidores; un servidor caído no bloquea a los demás.
  Future<List<SourceLibraries>> loadAllLibraries({bool refresh = false}) async {
    if (!refresh && _libraryCache != null) return _libraryCache!;
    final result = await Future.wait(
      sources.map((source) async {
        if (!hasSecret(source.id)) {
          return SourceLibraries(source, const [], 'Falta la API key en este dispositivo', true);
        }
        try {
          final libs = await client(source.id).libraries();
          return SourceLibraries(source, libs.map((l) => LibraryEntry(source, l)).toList());
        } catch (e) {
          return SourceLibraries(source, const [], e.toString());
        }
      }),
    );
    _libraryCache = result;
    return result;
  }

  String? libraryName(String sourceId, String libraryId) {
    for (final group in _libraryCache ?? const <SourceLibraries>[]) {
      for (final e in group.libraries) {
        if (e.source.id == sourceId && e.library.id == libraryId) return e.library.name;
      }
    }
    return null;
  }

  /// Libros empezados de todos los servidores, los leídos más recientemente primero.
  Future<List<SourcedBook>> continueReading() async {
    final perSource = await Future.wait(
      sources.where((s) => hasSecret(s.id)).map((source) async {
        try {
          final books = await client(source.id).inProgressBooks();
          return books.map((b) => SourcedBook(source, b)).toList();
        } catch (_) {
          return <SourcedBook>[];
        }
      }),
    );
    final all = perSource.expand((e) => e).toList()
      ..sort((a, b) => (b.book.readDate ?? DateTime(0)).compareTo(a.book.readDate ?? DateTime(0)));
    return all.take(20).toList();
  }

  // ---- Modo de lectura (se sincroniza con los datos del usuario) ----

  static ReadingMode _guessMode(String libraryName) {
    final n = libraryName.toLowerCase();
    const verticalHints = ['manhwa', 'manwha', 'webtoon', 'manhua'];
    return verticalHints.any(n.contains) ? ReadingMode.vertical : ReadingMode.pagedRtl;
  }

  ReadingMode? _readMode(String key) {
    final v = data.pref(key);
    return v == null ? null : ReadingMode.values.asNameMap()[v];
  }

  ReadingMode libraryMode(String sourceId, KomgaLibrary library) =>
      _readMode('libmode:$sourceId:${library.id}') ?? _guessMode(library.name);

  void setLibraryMode(String sourceId, String libraryId, ReadingMode mode) =>
      data.setPref('libmode:$sourceId:$libraryId', mode.name);

  /// Modo propio de la serie, o null si hereda el de la biblioteca.
  ReadingMode? seriesModeOverride(String sourceId, String seriesId) => _readMode('seriesmode:$sourceId:$seriesId');

  void setSeriesMode(String sourceId, String seriesId, ReadingMode? mode) =>
      data.setPref('seriesmode:$sourceId:$seriesId', mode?.name);

  /// Modo efectivo para leer un libro de una serie.
  Future<ReadingMode> effectiveMode(String sourceId, String libraryId, String seriesId) async {
    final override = seriesModeOverride(sourceId, seriesId);
    if (override != null) return override;
    final stored = _readMode('libmode:$sourceId:$libraryId');
    if (stored != null) return stored;
    final name =
        libraryName(sourceId, libraryId) ??
        downloads.all.where((b) => b.sourceId == sourceId && b.libraryId == libraryId).firstOrNull?.libraryName;
    if (name != null) return _guessMode(name);
    try {
      final libs = await client(sourceId).libraries();
      return _guessMode(libs.firstWhere((l) => l.id == libraryId).name);
    } catch (_) {
      return ReadingMode.pagedRtl;
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../komga/komga_client.dart';
import '../komga/models.dart';

/// Un libro guardado en el dispositivo para leer sin conexión.
class DownloadedBook {
  final String sourceId;
  final String bookId;
  final String seriesId;
  final String seriesTitle;
  final String libraryId;
  final String? libraryName;
  final String title;
  final String number;
  final List<KomgaPageInfo> pages;
  final Map<int, String> pageFiles; // nº de página -> nombre de fichero
  final int sizeBytes;
  final int downloadedAt;

  const DownloadedBook({
    required this.sourceId,
    required this.bookId,
    required this.seriesId,
    required this.seriesTitle,
    required this.libraryId,
    required this.libraryName,
    required this.title,
    required this.number,
    required this.pages,
    required this.pageFiles,
    required this.sizeBytes,
    required this.downloadedAt,
  });

  String get key => DownloadManager.keyOf(sourceId, bookId);

  /// Representación como libro de Komga, para el lector y las rejillas.
  KomgaBook toKomgaBook({KomgaReadProgress? progress}) => KomgaBook(
    id: bookId,
    seriesId: seriesId,
    seriesTitle: seriesTitle,
    libraryId: libraryId,
    title: title,
    number: number,
    pagesCount: pages.length,
    readProgress: progress,
  );

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'bookId': bookId,
    'seriesId': seriesId,
    'seriesTitle': seriesTitle,
    'libraryId': libraryId,
    'libraryName': libraryName,
    'title': title,
    'number': number,
    'pages': [
      for (final p in pages) {'number': p.number, 'width': p.width, 'height': p.height, 'file': pageFiles[p.number]},
    ],
    'sizeBytes': sizeBytes,
    'downloadedAt': downloadedAt,
  };

  factory DownloadedBook.fromJson(Map<String, dynamic> j) {
    final pages = (j['pages'] as List).cast<Map<String, dynamic>>();
    return DownloadedBook(
      sourceId: j['sourceId'] as String,
      bookId: j['bookId'] as String,
      seriesId: j['seriesId'] as String,
      seriesTitle: j['seriesTitle'] as String? ?? '',
      libraryId: j['libraryId'] as String,
      libraryName: j['libraryName'] as String?,
      title: j['title'] as String,
      number: j['number'] as String? ?? '',
      pages: [for (final p in pages) KomgaPageInfo.fromJson(p)],
      pageFiles: {for (final p in pages) p['number'] as int: p['file'] as String},
      sizeBytes: j['sizeBytes'] as int? ?? 0,
      downloadedAt: j['downloadedAt'] as int? ?? 0,
    );
  }
}

class _Job {
  final KomgaClient client;
  final KomgaBook book;
  final String? libraryName;
  bool cancelled = false;

  _Job(this.client, this.book, this.libraryName);
}

/// Descarga libros página a página y guarda el progreso de lectura que no se
/// pudo enviar a Komga por falta de conexión.
///
/// Estructura en disco: `downloads/<servidor>/<libro>/` con las páginas,
/// `cover.*` y `manifest.json` (que solo se escribe al terminar).
class DownloadManager extends ChangeNotifier {
  static const _parallelPages = 4;

  late Directory _root;
  final Map<String, DownloadedBook> _done = {};
  final List<_Job> _queue = [];
  final Map<String, double> _progress = {}; // clave -> 0..1 de los que están en cola
  _Job? _current;

  /// Progreso que falta por enviar a Komga: clave -> (página, completado).
  final Map<String, ({int page, bool completed})> _pendingProgress = {};
  late File _pendingFile;

  static String keyOf(String sourceId, String bookId) => '$sourceId|$bookId';

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _root = Directory('${support.path}${Platform.pathSeparator}downloads');
    await _root.create(recursive: true);
    _pendingFile = File('${support.path}${Platform.pathSeparator}pending_progress.json');
    await for (final sourceDir in _root.list()) {
      if (sourceDir is! Directory) continue;
      await for (final bookDir in sourceDir.list()) {
        if (bookDir is! Directory) continue;
        final manifest = File('${bookDir.path}${Platform.pathSeparator}manifest.json');
        if (await manifest.exists()) {
          try {
            final b = DownloadedBook.fromJson(jsonDecode(await manifest.readAsString()) as Map<String, dynamic>);
            _done[b.key] = b;
            continue;
          } catch (_) {}
        }
        // Descarga a medias de una sesión anterior: se descarta.
        await bookDir.delete(recursive: true);
      }
    }
    if (await _pendingFile.exists()) {
      try {
        (jsonDecode(await _pendingFile.readAsString()) as Map<String, dynamic>).forEach((k, v) {
          final m = v as Map<String, dynamic>;
          _pendingProgress[k] = (page: m['page'] as int, completed: m['completed'] as bool);
        });
      } catch (_) {}
    }
  }

  Directory _bookDir(String sourceId, String bookId) =>
      Directory('${_root.path}${Platform.pathSeparator}$sourceId${Platform.pathSeparator}$bookId');

  // ---- Consultas ----

  bool isDownloaded(String sourceId, String bookId) => _done.containsKey(keyOf(sourceId, bookId));
  DownloadedBook? downloaded(String sourceId, String bookId) => _done[keyOf(sourceId, bookId)];

  /// null si no está en cola; 0..1 si se está descargando o espera.
  double? progressOf(String sourceId, String bookId) => _progress[keyOf(sourceId, bookId)];

  bool get busy => _queue.isNotEmpty || _current != null;
  int get queuedCount => _queue.length + (_current == null ? 0 : 1);

  List<DownloadedBook> get all => _done.values.toList();

  List<DownloadedBook> ofSeries(String sourceId, String seriesId) =>
      _done.values.where((b) => b.sourceId == sourceId && b.seriesId == seriesId).toList()..sort((a, b) {
        final na = double.tryParse(a.number), nb = double.tryParse(b.number);
        return (na != null && nb != null) ? na.compareTo(nb) : a.title.compareTo(b.title);
      });

  int get totalBytes => _done.values.fold(0, (a, b) => a + b.sizeBytes);

  File pageFile(DownloadedBook b, int page) =>
      File('${_bookDir(b.sourceId, b.bookId).path}${Platform.pathSeparator}${b.pageFiles[page]}');

  File? coverFile(String sourceId, String bookId) {
    final dir = _bookDir(sourceId, bookId);
    for (final ext in ['jpg', 'png', 'webp', 'gif', 'img']) {
      final f = File('${dir.path}${Platform.pathSeparator}cover.$ext');
      if (f.existsSync()) return f;
    }
    return null;
  }

  // ---- Acciones ----

  /// Añade libros a la cola (los ya descargados o en cola se ignoran).
  void enqueue(KomgaClient client, Iterable<KomgaBook> books, {String? libraryName}) {
    for (final b in books) {
      final key = keyOf(client.source.id, b.id);
      if (_done.containsKey(key) || _progress.containsKey(key)) continue;
      _queue.add(_Job(client, b, libraryName));
      _progress[key] = 0;
    }
    notifyListeners();
    _pump();
  }

  void cancel(String sourceId, String bookId) {
    final key = keyOf(sourceId, bookId);
    _queue.removeWhere((j) => keyOf(j.client.source.id, j.book.id) == key);
    if (_current != null && keyOf(_current!.client.source.id, _current!.book.id) == key) {
      _current!.cancelled = true;
    }
    _progress.remove(key);
    notifyListeners();
  }

  void cancelAll() {
    _queue.clear();
    _current?.cancelled = true;
    _progress.clear();
    notifyListeners();
  }

  Future<void> delete(String sourceId, String bookId) async {
    cancel(sourceId, bookId);
    _done.remove(keyOf(sourceId, bookId));
    notifyListeners();
    final dir = _bookDir(sourceId, bookId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> deleteAll() async {
    cancelAll();
    final keys = _done.values.toList();
    _done.clear();
    notifyListeners();
    for (final b in keys) {
      final dir = _bookDir(b.sourceId, b.bookId);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  Future<void> _pump() async {
    if (_current != null || _queue.isEmpty) return;
    final job = _current = _queue.removeAt(0);
    final key = keyOf(job.client.source.id, job.book.id);
    try {
      await _download(job, key);
    } catch (e) {
      debugPrint('Descarga fallida ${job.book.title}: $e');
      final dir = _bookDir(job.client.source.id, job.book.id);
      if (await dir.exists()) await dir.delete(recursive: true);
    } finally {
      _progress.remove(key);
      _current = null;
      notifyListeners();
      unawaited(_pump());
    }
  }

  static String _ext(String? contentType) => switch (contentType?.split(';').first.trim()) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'image/avif' => 'avif',
    'image/jxl' => 'jxl',
    _ => 'img',
  };

  Future<void> _download(_Job job, String key) async {
    final client = job.client;
    final book = job.book;
    final dir = _bookDir(client.source.id, book.id);
    await dir.create(recursive: true);
    final pages = await client.pages(book.id);
    final files = <int, String>{};
    var size = 0;
    var done = 0;

    // Portada (no crítica).
    try {
      final (bytes, type) = await client.getBytes(client.bookThumbnailUrl(book.id));
      await File('${dir.path}${Platform.pathSeparator}cover.${_ext(type)}').writeAsBytes(bytes);
    } catch (_) {}

    var next = 0;
    Future<void> worker() async {
      while (next < pages.length) {
        if (job.cancelled) throw Exception('cancelada');
        final p = pages[next++];
        final (bytes, type) = await client.getBytes(client.pageUrl(book.id, p.number));
        final name = 'p${p.number.toString().padLeft(4, '0')}.${_ext(type)}';
        await File('${dir.path}${Platform.pathSeparator}$name').writeAsBytes(bytes, flush: true);
        files[p.number] = name;
        size += bytes.length;
        done++;
        if (_progress.containsKey(key)) {
          _progress[key] = done / pages.length;
          notifyListeners();
        }
      }
    }

    await Future.wait(List.generate(_parallelPages, (_) => worker()));
    if (job.cancelled) throw Exception('cancelada');

    final downloaded = DownloadedBook(
      sourceId: client.source.id,
      bookId: book.id,
      seriesId: book.seriesId,
      seriesTitle: book.seriesTitle,
      libraryId: book.libraryId,
      libraryName: job.libraryName,
      title: book.title,
      number: book.number,
      pages: pages,
      pageFiles: files,
      sizeBytes: size,
      downloadedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await File('${dir.path}${Platform.pathSeparator}manifest.json')
        .writeAsString(jsonEncode(downloaded.toJson()), flush: true);
    _done[key] = downloaded;
  }

  // ---- Progreso pendiente (sin conexión) ----

  /// Último progreso conocido localmente que aún no ha llegado a Komga.
  ({int page, bool completed})? pendingProgress(String sourceId, String bookId) =>
      _pendingProgress[keyOf(sourceId, bookId)];

  void queueProgress(String sourceId, String bookId, int page, bool completed) {
    _pendingProgress[keyOf(sourceId, bookId)] = (page: page, completed: completed);
    _savePending();
  }

  /// Olvida el progreso pendiente (p. ej. al marcar el libro como leído/no leído a mano).
  void discardPendingProgress(String sourceId, String bookId) {
    if (_pendingProgress.remove(keyOf(sourceId, bookId)) != null) _savePending();
  }

  /// Quita el pendiente si sigue siendo el de [page] (no uno más nuevo).
  void clearPendingProgress(String sourceId, String bookId, int page) {
    final key = keyOf(sourceId, bookId);
    if (_pendingProgress[key]?.page != page) return;
    _pendingProgress.remove(key);
    _savePending();
  }

  Future<void> _savePending() => _pendingFile.writeAsString(
    jsonEncode(_pendingProgress.map((k, v) => MapEntry(k, {'page': v.page, 'completed': v.completed}))),
  );

  /// Intenta enviar a Komga el progreso guardado sin conexión.
  Future<void> flushPendingProgress(KomgaClient? Function(String sourceId) clientFor) async {
    for (final entry in _pendingProgress.entries.toList()) {
      final [sourceId, bookId] = entry.key.split('|');
      final client = clientFor(sourceId);
      if (client == null) continue;
      try {
        await client.markProgress(bookId, page: entry.value.page, completed: entry.value.completed);
        _pendingProgress.remove(entry.key);
      } catch (_) {
        // Sigue sin conexión con ese servidor: se reintenta más tarde.
      }
    }
    await _savePending();
  }
}

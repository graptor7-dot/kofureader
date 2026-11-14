import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';

/// Id de "servidor" para las novelas (para ocultar bibliotecas, como con Komga).
const novelsSourceId = 'novels';

class NovelLibrary {
  final String id;
  final String name;
  final int works;

  NovelLibrary(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      works = j['works'] as int? ?? 0;
}

class NovelWork {
  final String lib;
  final String id;
  final String title;
  final int chapters;
  final bool hasCover;
  final DateTime updatedAt;

  NovelWork(this.lib, Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      chapters = j['chapters'] as int? ?? 0,
      hasCover = j['hasCover'] == true,
      updatedAt = DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int? ?? 0);

  String get key => '$lib/$id';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'chapters': chapters,
    'hasCover': hasCover,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

class NovelChapter {
  final String id; // ruta relativa dentro de la obra
  final String title;
  final int? number;
  final String? volume;

  NovelChapter(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      number = j['number'] as int?,
      volume = j['volume'] as String?;

  String get label => number == null ? title : '$number · $title';

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'number': number, 'volume': volume};
}

/// Novelas que sirve KofuSync desde la carpeta del NAS, y su progreso de lectura
/// (guardado como preferencias sincronizadas entre dispositivos).
class NovelService extends ChangeNotifier {
  final AppState state;

  NovelService(this.state);

  bool get available => state.sync.configured || _offline.isNotEmpty;

  // ---- Descargas (sin conexión) ----
  //
  // <soporte>/novels/<n>/work.json   {lib, libName, work, chapters, files: {id: fichero}}
  // <soporte>/novels/<n>/cover       portada
  // <soporte>/novels/<n>/<i>.txt     texto de cada capítulo

  Directory? _root;
  final Map<
    String,
    ({Directory dir, String libName, NovelWork work, List<NovelChapter> chapters, Map<String, String> files})
  >
  _offline = {};
  final Map<String, double> _progress = {}; // descargas en curso (0..1)

  Future<void> init() async {
    try {
      _root = Directory('${(await getApplicationSupportDirectory()).path}/novels');
      if (!_root!.existsSync()) return;
      for (final dir in _root!.listSync().whereType<Directory>()) {
        try {
          _loadOffline(dir);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _loadOffline(Directory dir) {
    final j = jsonDecode(File('${dir.path}/work.json').readAsStringSync()) as Map<String, dynamic>;
    final work = NovelWork(j['lib'] as String, j['work'] as Map<String, dynamic>);
    _offline[work.key] = (
      dir: dir,
      libName: j['libName'] as String? ?? work.lib,
      work: work,
      chapters: [for (final c in (j['chapters'] as List).cast<Map<String, dynamic>>()) NovelChapter(c)],
      files: (j['files'] as Map).cast<String, String>(),
    );
  }

  bool isDownloaded(NovelWork work) => _offline.containsKey(work.key);

  /// Progreso de la descarga en curso (null si no se está descargando).
  double? downloadProgress(NovelWork work) => _progress[work.key];

  /// Descarga todos los capítulos (y la portada) para leer sin conexión.
  Future<void> download(NovelWork work, {String? libName}) async {
    if (_progress.containsKey(work.key) || _root == null) return;
    _progress[work.key] = 0;
    notifyListeners();
    final dir = Directory('${_root!.path}/${DateTime.now().microsecondsSinceEpoch}');
    try {
      final chapters = await this.chapters(work);
      await dir.create(recursive: true);
      final files = <String, String>{};
      for (final (i, c) in chapters.indexed) {
        final text = await _fetchChapter(work, c);
        await File('${dir.path}/$i.txt').writeAsString(text);
        files[c.id] = '$i.txt';
        _progress[work.key] = (i + 1) / chapters.length;
        notifyListeners();
      }
      if (work.hasCover) {
        try {
          final res = await http.get(Uri.parse(coverUrl(work)), headers: headers).timeout(const Duration(seconds: 30));
          if (res.statusCode == 200) await File('${dir.path}/cover').writeAsBytes(res.bodyBytes);
        } catch (_) {}
      }
      final old = _offline[work.key]?.dir;
      await File('${dir.path}/work.json').writeAsString(
        jsonEncode({
          'lib': work.lib,
          'libName': libName ?? _offline[work.key]?.libName ?? work.lib,
          'work': work.toJson(),
          'chapters': [for (final c in chapters) c.toJson()],
          'files': files,
        }),
      );
      _loadOffline(dir);
      if (old != null && old.path != dir.path) await old.delete(recursive: true).catchError((_) => old);
    } catch (e) {
      await dir.delete(recursive: true).catchError((_) => dir);
      rethrow;
    } finally {
      _progress.remove(work.key);
      notifyListeners();
    }
  }

  Future<void> removeDownload(NovelWork work) async {
    final o = _offline.remove(work.key);
    notifyListeners();
    if (o != null) await o.dir.delete(recursive: true).catchError((_) => o.dir);
  }

  String offlineLibraryName(NovelWork work) => _offline[work.key]?.libName ?? work.lib;

  /// Obras descargadas (para la pantalla de descargas).
  List<NovelWork> get downloadedWorks => [for (final o in _offline.values) o.work];

  File? offlineCover(NovelWork work) {
    final o = _offline[work.key];
    if (o == null) return null;
    final f = File('${o.dir.path}/cover');
    return f.existsSync() ? f : null;
  }

  Map<String, String> get headers => {'Authorization': 'Bearer ${state.sync.token}'};

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(state.sync.url!);
    return base.replace(path: '${base.path}$path', queryParameters: query);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final res = await http.get(_uri(path, query), headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode == 404 && path == '/novels') {
      throw Exception('Actualiza KofuSync en el servidor para ver las novelas');
    }
    if (res.statusCode != 200) throw Exception('KofuSync respondió ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<List<NovelLibrary>> libraries() async {
    try {
      if (!state.sync.configured) throw Exception('Sin KofuSync');
      final j = await _get('/novels') as Map<String, dynamic>;
      return [for (final l in (j['libraries'] as List).cast<Map<String, dynamic>>()) NovelLibrary(l)];
    } catch (_) {
      // Sin conexión: las bibliotecas de lo descargado.
      if (_offline.isEmpty) rethrow;
      final libs = <String, String>{for (final o in _offline.values) o.work.lib: o.libName};
      return [
        for (final e in libs.entries)
          NovelLibrary({
            'id': e.key,
            'name': e.value,
            'works': _offline.values.where((o) => o.work.lib == e.key).length,
          }),
      ];
    }
  }

  Future<List<NovelWork>> works(String lib) async {
    try {
      if (!state.sync.configured) throw Exception('Sin KofuSync');
      final j = await _get('/novels/works', {'lib': lib}) as Map<String, dynamic>;
      return [for (final w in (j['works'] as List).cast<Map<String, dynamic>>()) NovelWork(lib, w)];
    } catch (_) {
      final local = [
        for (final o in _offline.values)
          if (o.work.lib == lib) o.work,
      ];
      if (local.isEmpty) rethrow;
      return local;
    }
  }

  Future<List<NovelChapter>> chapters(NovelWork work) async {
    try {
      if (!state.sync.configured) throw Exception('Sin KofuSync');
      final j = await _get('/novels/chapters', {'lib': work.lib, 'work': work.id}) as Map<String, dynamic>;
      return [for (final c in (j['chapters'] as List).cast<Map<String, dynamic>>()) NovelChapter(c)];
    } catch (_) {
      final o = _offline[work.key];
      if (o == null) rethrow;
      return o.chapters;
    }
  }

  /// Texto de un capítulo: del disco si está descargado, si no de KofuSync.
  Future<String> chapterText(NovelWork work, NovelChapter chapter) async {
    final o = _offline[work.key];
    final name = o?.files[chapter.id];
    if (o != null && name != null) {
      final f = File('${o.dir.path}/$name');
      if (f.existsSync()) return f.readAsString();
    }
    return _fetchChapter(work, chapter);
  }

  // ---- Búsqueda de texto ----

  /// Capítulos donde aparece [query] (sin distinguir mayúsculas ni tildes).
  Future<NovelSearchResult> search(NovelWork work, String query) async {
    final o = _offline[work.key];
    if (o != null) {
      final hits = <NovelSearchHit>[];
      var total = 0;
      final q = foldText(query.trim());
      for (final c in o.chapters) {
        final name = o.files[c.id];
        if (name == null) continue;
        final text = await File('${o.dir.path}/$name').readAsString();
        final folded = foldText(text);
        final shown = folded.length == text.length ? text : folded;
        final snippets = <String>[];
        var count = 0;
        for (var i = folded.indexOf(q); i >= 0; i = folded.indexOf(q, i + q.length)) {
          count++;
          if (snippets.length < 3) snippets.add(_snippet(shown, i, q.length));
        }
        if (count == 0) continue;
        total += count;
        hits.add(NovelSearchHit(c.id, c.title, c.number, count, snippets));
      }
      return NovelSearchResult(total, hits);
    }
    final res = await http
        .get(_uri('/novels/search', {'lib': work.lib, 'work': work.id, 'q': query.trim()}), headers: headers)
        .timeout(const Duration(seconds: 60));
    if (res.statusCode == 404) throw Exception('Actualiza KofuSync en el servidor para buscar en las novelas');
    if (res.statusCode != 200) throw Exception('KofuSync respondió ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return NovelSearchResult(j['total'] as int? ?? 0, [
      for (final h in (j['results'] as List).cast<Map<String, dynamic>>())
        NovelSearchHit(
          h['id'] as String,
          h['title'] as String,
          h['number'] as int?,
          h['count'] as int? ?? 0,
          (h['snippets'] as List).cast<String>(),
        ),
    ]);
  }

  static String _snippet(String text, int at, int length) {
    final start = (at - 70).clamp(0, text.length);
    final end = (at + length + 70).clamp(0, text.length);
    String clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').replaceAll('#', '');
    return '${start > 0 ? '…' : ''}${clean(text.substring(start, at))}[[${text.substring(at, at + length)}]]'
        '${clean(text.substring(at + length, end))}${end < text.length ? '…' : ''}';
  }

  Future<String> _fetchChapter(NovelWork work, NovelChapter chapter) async {
    final res = await http
        .get(_uri('/novels/chapter', {'lib': work.lib, 'work': work.id, 'ch': chapter.id}), headers: headers)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('No se pudo cargar el capítulo (${res.statusCode})');
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  String coverUrl(NovelWork work) => _uri('/novels/cover', {'lib': work.lib, 'work': work.id}).toString();

  // ---- Progreso (sincronizado) ----

  String _key(String kind, NovelWork work, [NovelChapter? ch]) =>
      ch == null ? 'novel$kind:${work.key}' : 'novel$kind:${work.key}/${ch.id}';

  /// Fracción leída del capítulo (0..1), o null si no se ha empezado.
  double? position(NovelWork work, NovelChapter ch) => double.tryParse(state.data.pref(_key('pos', work, ch)) ?? '');

  bool isRead(NovelWork work, NovelChapter ch) => state.data.pref(_key('read', work, ch)) == '1';

  void savePosition(NovelWork work, NovelChapter ch, double fraction) {
    state.data.setPref(_key('pos', work, ch), fraction.toStringAsFixed(4));
    if (state.data.pref(_key('last', work)) != ch.id) state.data.setPref(_key('last', work), ch.id);
    state.data.setPref(_key('lastat', work), DateTime.now().millisecondsSinceEpoch.toString());
    if (fraction >= 0.97 && !isRead(work, ch)) setRead(work, ch, true);
  }

  void setRead(NovelWork work, NovelChapter ch, bool read) {
    state.data.setPref(_key('read', work, ch), read ? '1' : null);
    state.data.setPref(_key('readat', work, ch), read ? DateTime.now().millisecondsSinceEpoch.toString() : null);
  }

  /// Cuándo se leyó por última vez la obra.
  DateTime? lastReadAt(NovelWork work) {
    final ms = int.tryParse(state.data.pref(_key('lastat', work)) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Fechas en que se terminaron capítulos de novela (para las estadísticas).
  List<DateTime> readDates() => [
    for (final k in state.data.prefKeys.where((k) => k.startsWith('novelreadat:')))
      if (int.tryParse(state.data.pref(k) ?? '') case final ms?) DateTime.fromMillisecondsSinceEpoch(ms),
  ];

  /// Obras empezadas: el capítulo a medias (Seguir leyendo) o el siguiente sin empezar (Te toca).
  Future<({List<NovelProgress> reading, List<NovelProgress> upNext})> progress() async {
    final reading = <NovelProgress>[], upNext = <NovelProgress>[];
    if (!available) return (reading: reading, upNext: upNext);
    for (final lib in await libraries()) {
      if (state.isLibraryHidden(novelsSourceId, lib.id)) continue;
      for (final work in (await works(lib.id)).where(started)) {
        final chapters = await this.chapters(work);
        final i = chapters.indexWhere((c) => c.id == lastChapterId(work));
        if (i < 0) continue;
        final at = lastReadAt(work) ?? DateTime(2000);
        if (!isRead(work, chapters[i])) {
          reading.add(NovelProgress(work, chapters, i, position(work, chapters[i]) ?? 0, at));
        } else if (i + 1 < chapters.length && !isRead(work, chapters[i + 1])) {
          upNext.add(NovelProgress(work, chapters, i + 1, 0, at));
        }
      }
    }
    return (reading: reading, upNext: upNext);
  }

  /// Último capítulo abierto de la obra (para "Continuar").
  String? lastChapterId(NovelWork work) => state.data.pref(_key('last', work));

  bool started(NovelWork work) => lastChapterId(work) != null;
}

/// Minúsculas y sin tildes, carácter a carácter (las posiciones no cambian).
String foldText(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final out = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = from.indexOf(c);
    out.write(i < 0 ? c : to[i]);
  }
  return out.toString();
}

class NovelSearchHit {
  final String chapterId;
  final String title;
  final int? number;
  final int count;
  final List<String> snippets; // la coincidencia va entre [[ ]]

  NovelSearchHit(this.chapterId, this.title, this.number, this.count, this.snippets);
}

class NovelSearchResult {
  final int total;
  final List<NovelSearchHit> hits;

  NovelSearchResult(this.total, this.hits);
}

/// Un capítulo de novela para las filas del inicio.
class NovelProgress {
  final NovelWork work;
  final List<NovelChapter> chapters;
  final int index;
  final double fraction;
  final DateTime at;

  NovelProgress(this.work, this.chapters, this.index, this.fraction, this.at);

  NovelChapter get chapter => chapters[index];
}

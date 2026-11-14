import 'dart:convert';

import 'package:http/http.dart' as http;

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
}

/// Novelas que sirve KofuSync desde la carpeta del NAS, y su progreso de lectura
/// (guardado como preferencias sincronizadas entre dispositivos).
class NovelService {
  final AppState state;

  NovelService(this.state);

  bool get available => state.sync.configured;

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
    final j = await _get('/novels') as Map<String, dynamic>;
    return [for (final l in (j['libraries'] as List).cast<Map<String, dynamic>>()) NovelLibrary(l)];
  }

  Future<List<NovelWork>> works(String lib) async {
    final j = await _get('/novels/works', {'lib': lib}) as Map<String, dynamic>;
    return [for (final w in (j['works'] as List).cast<Map<String, dynamic>>()) NovelWork(lib, w)];
  }

  Future<List<NovelChapter>> chapters(NovelWork work) async {
    final j = await _get('/novels/chapters', {'lib': work.lib, 'work': work.id}) as Map<String, dynamic>;
    return [for (final c in (j['chapters'] as List).cast<Map<String, dynamic>>()) NovelChapter(c)];
  }

  Future<String> chapterText(NovelWork work, NovelChapter chapter) async {
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
    state.data.setPref(_key('last', work), ch.id);
    if (fraction >= 0.97 && !isRead(work, ch)) setRead(work, ch, true);
  }

  void setRead(NovelWork work, NovelChapter ch, bool read) =>
      state.data.setPref(_key('read', work, ch), read ? '1' : null);

  /// Último capítulo abierto de la obra (para "Continuar").
  String? lastChapterId(NovelWork work) => state.data.pref(_key('last', work));

  bool started(NovelWork work) => lastChapterId(work) != null;
}

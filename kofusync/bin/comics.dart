part of 'server.dart';

// ---------------------------------------------------------------------------
// Tags de cómics: KofuSync lee el ComicInfo.xml de los .cbz de una carpeta
// (montada en solo lectura) sin que Komga tenga que importar sus metadatos.
//
//   GET /comics/tags   (con el token) -> {"files": {"Autor/archivo.cbz": ["tag", …]},
//                                         "scanning": bool, "count": n}
//
// La app empareja cada libro de Komga por el final de su ruta (carpeta/archivo).
// Se guarda una caché en /data con la fecha y el tamaño de cada archivo, así
// solo se vuelven a abrir los que cambian.
// ---------------------------------------------------------------------------

late final Directory _comicsRoot;
late final File _comicsCacheFile;

/// ruta relativa -> {m: modificado (ms), s: tamaño, t: tags}
final Map<String, Map<String, dynamic>> _comicsIndex = {};
DateTime? _comicsScannedAt;
Future<void>? _comicsScan;

const _comicExtensions = {'.cbz', '.zip'};

void _initComics(Directory dataDir) {
  _comicsRoot = Directory(Platform.environment['KOFUSYNC_COMICS'] ?? '/comics');
  _comicsCacheFile = File('${dataDir.path}/comicinfo-cache.json');
  try {
    if (_comicsCacheFile.existsSync()) {
      final json = jsonDecode(_comicsCacheFile.readAsStringSync()) as Map<String, dynamic>;
      for (final e in json.entries) {
        _comicsIndex[e.key] = (e.value as Map).cast<String, dynamic>();
      }
    }
  } catch (_) {}
  if (_comicsRoot.existsSync()) _startComicsScan();
}

void _startComicsScan() {
  _comicsScan ??= _scanComics().whenComplete(() => _comicsScan = null);
}

Future<void> _scanComics() async {
  final root = _comicsRoot.path.endsWith('/') ? _comicsRoot.path : '${_comicsRoot.path}/';
  final seen = <String>{};
  var changed = false;
  var sinceSave = 0;
  await for (final entity in _comicsRoot.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_comicExtensions.contains(_ext(entity.path))) continue;
    final rel = entity.path.substring(root.length).replaceAll('\\', '/');
    seen.add(rel);
    final FileStat stat;
    try {
      stat = await entity.stat();
    } catch (_) {
      continue;
    }
    final m = stat.modified.millisecondsSinceEpoch;
    final old = _comicsIndex[rel];
    if (old != null && old['m'] == m && old['s'] == stat.size) continue;
    _comicsIndex[rel] = {'m': m, 's': stat.size, 't': _readComicTags(entity.path)};
    changed = true;
    // Guardar de vez en cuando en el primer escaneo (puede ser largo).
    if (++sinceSave >= 200) {
      sinceSave = 0;
      await _saveComicsCache();
    }
    // Dejar respirar al servidor entre archivo y archivo.
    await Future<void>.delayed(Duration.zero);
  }
  final gone = _comicsIndex.keys.where((k) => !seen.contains(k)).toList();
  for (final k in gone) {
    _comicsIndex.remove(k);
  }
  if (changed || gone.isNotEmpty) await _saveComicsCache();
  _comicsScannedAt = DateTime.now();
}

Future<void> _saveComicsCache() async {
  final tmp = File('${_comicsCacheFile.path}.tmp');
  await tmp.writeAsString(jsonEncode(_comicsIndex), flush: true);
  await tmp.rename(_comicsCacheFile.path);
}

/// Tags del ComicInfo.xml de un .cbz (sin leer el archivo entero: solo el índice del zip).
List<String> _readComicTags(String path) {
  InputFileStream? input;
  try {
    input = InputFileStream(path);
    final zip = ZipDecoder().decodeStream(input);
    final entry = zip.files.where((f) => f.name.split('/').last.toLowerCase() == 'comicinfo.xml').firstOrNull;
    if (entry == null) return const [];
    final xml = utf8.decode(entry.content as List<int>, allowMalformed: true);
    return _comicInfoTags(xml);
  } catch (_) {
    return const [];
  } finally {
    input?.closeSync();
  }
}

/// Tags de <Tags> (y <Genre>, que algunos programas usan igual), en minúsculas, sin repetir.
List<String> _comicInfoTags(String xml) {
  final out = <String>{};
  for (final field in ['Tags', 'Genre']) {
    final m = RegExp('<$field>([\\s\\S]*?)</$field>').firstMatch(xml);
    if (m == null) continue;
    for (final raw in _xmlUnescape(m.group(1)!).split(RegExp(r'[,;]'))) {
      final t = raw.trim().toLowerCase();
      if (t.isNotEmpty && t != 'manga') out.add(t);
    }
  }
  return out.toList();
}

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

Future<void> _comics(HttpRequest req) async {
  if (!_authorized(req)) return _json(req, 401, {'error': 'unauthorized'});
  if (!_comicsRoot.existsSync()) return _json(req, 200, {'files': {}, 'configured': false});
  // Reescanear si hace más de 5 minutos (en segundo plano; se responde con lo que hay).
  final last = _comicsScannedAt;
  if (last == null || DateTime.now().difference(last).inMinutes >= 5) _startComicsScan();
  final files = <String, List<dynamic>>{
    for (final e in _comicsIndex.entries)
      if ((e.value['t'] as List?)?.isNotEmpty ?? false) e.key: e.value['t'] as List,
  };
  return _json(req, 200, {
    'configured': true,
    'scanning': _comicsScan != null,
    'count': _comicsIndex.length,
    'files': files,
  });
}

part of 'server.dart';

// ---------------------------------------------------------------------------
// Novelas: KofuSync sirve una carpeta de texto (montada en solo lectura).
//
//   /novels/<Biblioteca>/<Obra>/cover.jpg
//   /novels/<Biblioteca>/<Obra>/001 - Título.txt         (o .md, o .epub)
//   /novels/<Biblioteca>/<Obra>/Volumen 1/001 - ….txt    (subcarpetas opcionales)
//
// Rutas (con el token, como /sync):
//   GET /novels                              -> bibliotecas
//   GET /novels/works?lib=                   -> obras de una biblioteca
//   GET /novels/chapters?lib=&work=          -> capítulos (orden natural)
//   GET /novels/chapter?lib=&work=&ch=       -> texto de un capítulo
//   GET /novels/cover?lib=&work=             -> portada
//   GET /novels/search?lib=&work=&q=         -> capítulos donde aparece un texto
// ---------------------------------------------------------------------------

late final Directory _novelsRoot;

const _textExtensions = {'.txt', '.md', '.epub'};
const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

void _initNovels() {
  _novelsRoot = Directory(Platform.environment['KOFUSYNC_NOVELS'] ?? '/novels');
}

String _ext(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot).toLowerCase();
}

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

/// Un nombre de carpeta válido (sin barras ni "..").
bool _safeName(String? s) =>
    s != null &&
    s.isNotEmpty &&
    !s.contains('/') &&
    !s.contains('\\') &&
    s != '..' &&
    s != '.';

/// Orden "natural": "Capítulo 2" antes que "Capítulo 10".
int _naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]), nb = int.tryParse(pb[i]);
    final c = (na != null && nb != null)
        ? na.compareTo(nb)
        : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

Directory? _workDir(String? lib, String? work) {
  if (!_safeName(lib) || !_safeName(work)) return null;
  final dir = Directory('${_novelsRoot.path}/$lib/$work');
  return dir.existsSync() ? dir : null;
}

/// Capítulos de una obra: ficheros de texto en la carpeta y sus subcarpetas.
List<File> _chapterFiles(Directory work) {
  final files = work
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where(
        (f) =>
            _textExtensions.contains(_ext(f.path)) &&
            !_baseName(f.path).startsWith('.'),
      )
      .toList();
  String rel(File f) =>
      f.path.substring(work.path.length + 1).replaceAll('\\', '/');
  files.sort((a, b) => _naturalCompare(rel(a), rel(b)));
  return files;
}

/// "001 - El inicio.txt" -> (1, "El inicio"); "Capítulo 7.txt" -> (null, "Capítulo 7").
(int?, String) _chapterTitle(String fileName) {
  final name = fileName
      .substring(0, fileName.length - _ext(fileName).length)
      .trim();
  final m = RegExp(r'^(\d+)\s*[-_.:)]*\s*(.*)$').firstMatch(name);
  if (m == null) return (null, name);
  final number = int.parse(m.group(1)!);
  final rest = m.group(2)!.trim();
  return (number, rest.isEmpty ? 'Capítulo $number' : rest);
}

File? _coverFile(Directory work) {
  final images =
      work
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => _imageExtensions.contains(_ext(f.path)))
          .toList()
        ..sort((a, b) => _naturalCompare(_baseName(a.path), _baseName(b.path)));
  if (images.isEmpty) return null;
  return images.firstWhere(
    (f) => RegExp(
      r'^(cover|portada|folder)\.',
      caseSensitive: false,
    ).hasMatch(_baseName(f.path)),
    orElse: () => images.first,
  );
}

Future<void> _novels(HttpRequest req) async {
  if (!_authorized(req)) return _json(req, 401, {'error': 'unauthorized'});
  if (!_novelsRoot.existsSync())
    return _json(req, 200, {'libraries': [], 'configured': false});
  final q = req.uri.queryParameters;
  switch (req.uri.path) {
    case '/novels':
      final libs =
          _novelsRoot
              .listSync(followLinks: false)
              .whereType<Directory>()
              .toList()
            ..sort(
              (a, b) => _naturalCompare(_baseName(a.path), _baseName(b.path)),
            );
      return _json(req, 200, {
        'configured': true,
        'libraries': [
          for (final d in libs)
            if (!_baseName(d.path).startsWith('.'))
              {
                'id': _baseName(d.path),
                'name': _baseName(d.path),
                'works': d
                    .listSync(followLinks: false)
                    .whereType<Directory>()
                    .length,
              },
        ],
      });

    case '/novels/works':
      final lib = q['lib'];
      if (!_safeName(lib)) return _json(req, 400, {'error': 'bad lib'});
      final dir = Directory('${_novelsRoot.path}/$lib');
      if (!dir.existsSync()) return _json(req, 404, {'error': 'not found'});
      final works =
          dir.listSync(followLinks: false).whereType<Directory>().toList()
            ..sort(
              (a, b) => _naturalCompare(_baseName(a.path), _baseName(b.path)),
            );
      return _json(req, 200, {
        'works': [
          for (final w in works)
            if (!_baseName(w.path).startsWith('.'))
              () {
                final chapters = _chapterFiles(w);
                final updated = chapters.isEmpty
                    ? w.statSync().modified
                    : chapters
                          .map((f) => f.statSync().modified)
                          .reduce((a, b) => a.isAfter(b) ? a : b);
                return {
                  'id': _baseName(w.path),
                  'title': _baseName(w.path),
                  'chapters': chapters.length,
                  'hasCover': _coverFile(w) != null,
                  'updatedAt': updated.millisecondsSinceEpoch,
                };
              }(),
        ],
      });

    case '/novels/chapters':
      final work = _workDir(q['lib'], q['work']);
      if (work == null) return _json(req, 404, {'error': 'not found'});
      return _json(req, 200, {
        'chapters': [
          for (final f in _chapterFiles(work))
            () {
              final rel = f.path
                  .substring(work.path.length + 1)
                  .replaceAll('\\', '/');
              final parts = rel.split('/');
              final (number, title) = _chapterTitle(parts.last);
              return {
                'id': rel,
                'title': title,
                'number': number,
                'volume': parts.length > 1
                    ? parts.sublist(0, parts.length - 1).join(' / ')
                    : null,
                'size': f.lengthSync(),
              };
            }(),
        ],
      });

    case '/novels/chapter':
      final work = _workDir(q['lib'], q['work']);
      final ch = q['ch'] ?? '';
      if (work == null ||
          ch.isEmpty ||
          ch.split('/').any((p) => !_safeName(p))) {
        return _json(req, 404, {'error': 'not found'});
      }
      final file = File('${work.path}/$ch');
      if (!file.existsSync() || !_textExtensions.contains(_ext(file.path))) {
        return _json(req, 404, {'error': 'not found'});
      }
      final text = await _readChapter(file);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'plain', charset: 'utf-8')
        ..write(text);
      return req.response.close();

    case '/novels/search':
      final work = _workDir(q['lib'], q['work']);
      final query = _fold((q['q'] ?? '').trim());
      if (work == null) return _json(req, 404, {'error': 'not found'});
      if (query.length < 2)
        return _json(req, 400, {'error': 'query too short'});
      final results = <Map<String, Object?>>[];
      var total = 0;
      for (final f in _chapterFiles(work)) {
        final text = await _readChapter(f);
        final folded = _fold(text);
        final rel = f.path
            .substring(work.path.length + 1)
            .replaceAll('\\', '/');
        final snippets = <String>[];
        var count = 0;
        for (
          var i = folded.indexOf(query);
          i >= 0;
          i = folded.indexOf(query, i + query.length)
        ) {
          count++;
          if (snippets.length < 3)
            snippets.add(
              _snippet(
                folded.length == text.length ? text : folded,
                i,
                query.length,
              ),
            );
        }
        if (count == 0) continue;
        total += count;
        final (number, title) = _chapterTitle(rel.split('/').last);
        results.add({
          'id': rel,
          'title': title,
          'number': number,
          'count': count,
          'snippets': snippets,
        });
        if (results.length >= 200) break;
      }
      return _json(req, 200, {'total': total, 'results': results});

    case '/novels/cover':
      final work = _workDir(q['lib'], q['work']);
      final cover = work == null ? null : _coverFile(work);
      if (cover == null) return _json(req, 404, {'error': 'no cover'});
      final ext = _ext(cover.path);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType(
          'image',
          ext == '.jpg' ? 'jpeg' : ext.substring(1),
        )
        ..headers.set('Cache-Control', 'private, max-age=86400');
      await cover.openRead().pipe(req.response);
      return;
  }
  return _json(req, 404, {'error': 'not found'});
}

/// Texto de un capítulo (TXT/MD en UTF-8 o Latin-1, o EPUB convertido).
Future<String> _readChapter(File file) async {
  final bytes = await file.readAsBytes();
  String text;
  if (_ext(file.path) == '.epub') {
    text = _epubToText(bytes);
  } else {
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = latin1.decode(bytes); // TXT antiguos en ANSI/Latin-1
    }
  }
  if (text.startsWith('﻿')) text = text.substring(1);
  return text;
}

/// Minúsculas y sin tildes, carácter a carácter (las posiciones no cambian).
String _fold(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final out = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = from.indexOf(c);
    out.write(i < 0 ? c : to[i]);
  }
  return out.toString();
}

/// Fragmento alrededor de una coincidencia, marcada con [[ ]].
String _snippet(String text, int at, int length) {
  final start = (at - 70).clamp(0, text.length);
  final end = (at + length + 70).clamp(0, text.length);
  String clean(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').replaceAll('#', '');
  return '${start > 0 ? '…' : ''}${clean(text.substring(start, at))}[[${text.substring(at, at + length)}]]'
      '${clean(text.substring(at + length, end))}${end < text.length ? '…' : ''}';
}

/// Texto de un EPUB: los documentos del "spine" en orden, con párrafos separados
/// por una línea en blanco y los títulos como "# Título" (lo que espera la app).
String _epubToText(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? read(String path) {
    final f = zip.findFile(path);
    return f == null
        ? null
        : utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final container = read('META-INF/container.xml') ?? '';
  final opfPath = RegExp(
    r'full-path="([^"]+)"',
  ).firstMatch(container)?.group(1);
  final opf = opfPath == null ? null : read(opfPath);
  final docs = <String>[];
  if (opf != null) {
    final dir = opfPath!.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final manifest = <String, String>{};
    for (final m in RegExp(r'<item\b[^>]*>').allMatches(opf)) {
      final tag = m.group(0)!;
      final id = RegExp(r'\bid="([^"]+)"').firstMatch(tag)?.group(1);
      final href = RegExp(r'\bhref="([^"]+)"').firstMatch(tag)?.group(1);
      final props =
          RegExp(r'\bproperties="([^"]+)"').firstMatch(tag)?.group(1) ?? '';
      if (id != null && href != null && !props.contains('nav'))
        manifest[id] = '$dir${Uri.decodeFull(href)}';
    }
    for (final m in RegExp(
      r'<itemref\b[^>]*\bidref="([^"]+)"',
    ).allMatches(opf)) {
      final html = manifest[m.group(1)] == null
          ? null
          : read(manifest[m.group(1)]!);
      if (html != null) docs.add(html);
    }
  }
  if (docs.isEmpty) {
    // EPUB raro: todos los (x)html que haya.
    for (final f in zip.files.where(
      (f) => f.isFile && RegExp(r'\.x?html?$').hasMatch(f.name),
    )) {
      docs.add(utf8.decode(f.content as List<int>, allowMalformed: true));
    }
  }
  return docs.map(_htmlToText).join('\n\n').trim();
}

String _htmlToText(String html) {
  var s = html;
  final body = RegExp(
    r'<body[^>]*>([\s\S]*)</body>',
    caseSensitive: false,
  ).firstMatch(s);
  if (body != null) s = body.group(1)!;
  s = s.replaceAll(
    RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false),
    '',
  );
  s = s.replaceAllMapped(
    RegExp(r'<h[1-6][^>]*>([\s\S]*?)</h[1-6]>', caseSensitive: false),
    (m) => '\n\n# ${m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim()}\n\n',
  );
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<hr[^>]*>', caseSensitive: false), '\n\n***\n\n');
  s = s.replaceAll(
    RegExp(r'</(p|div|blockquote|li|section)>', caseSensitive: false),
    '\n\n',
  );
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      )
      .replaceAll('&amp;', '&');
  return s
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

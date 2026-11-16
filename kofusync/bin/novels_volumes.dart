part of 'server.dart';

// ---------------------------------------------------------------------------
// Novelas ligeras: van por tomos, un EPUB por tomo.
//
//   /novels/Novelas Ligeras/<Obra>/cover.jpg       portada general
//   /novels/Novelas Ligeras/<Obra>/Tomo 01.epub    cada tomo (portada y capítulos dentro)
//   /novels/Novelas Ligeras/<Obra>/Tomo 01.jpg     portada del tomo (opcional, gana a la del EPUB)
//
// Una biblioteca es "por tomos" si su nombre contiene "ligera" o "light".
//
//   GET /novels/volumes?lib=&work=             -> tomos
//   GET /novels/volcover?lib=&work=&vol=       -> portada del tomo
//   GET /novels/chapters?lib=&work=&vol=       -> capítulos del tomo (id = "<tomo>#<n>")
//   GET /novels/chapter?…&ch=<tomo>#<n>        -> texto de ese capítulo
// ---------------------------------------------------------------------------

bool _volumeLib(String? lib) =>
    lib != null && RegExp(r'liger|light', caseSensitive: false).hasMatch(lib);

/// Tomos de una obra: los EPUB de su carpeta, en orden natural.
List<File> _volumeFiles(Directory work) =>
    work
        .listSync(followLinks: false)
        .whereType<File>()
        .where(
          (f) => _ext(f.path) == '.epub' && !_baseName(f.path).startsWith('.'),
        )
        .toList()
      ..sort((a, b) => _naturalCompare(_baseName(a.path), _baseName(b.path)));

File? _volumeFile(Directory work, String? vol) {
  if (!_safeName(vol) || _ext(vol!) != '.epub') return null;
  final f = File('${work.path}/$vol');
  return f.existsSync() ? f : null;
}

String _stem(String fileName) =>
    fileName.substring(0, fileName.length - _ext(fileName).length);

/// Portada al lado del EPUB ("Tomo 01.jpg").
File? _volumeSidecarCover(File epub) {
  final stem = _stem(epub.path);
  for (final ext in _imageExtensions) {
    final f = File('$stem$ext');
    if (f.existsSync()) return f;
  }
  return null;
}

class _EpubChapter {
  final String title;
  final String text;

  _EpubChapter(this.title, this.text);
}

class _EpubBook {
  final List<_EpubChapter> chapters;
  final List<int>? cover;
  final String coverType;

  _EpubBook(this.chapters, this.cover, this.coverType);
}

// Los EPUB ya abiertos (se piden capítulo a capítulo): ruta -> (fecha, libro).
final _epubCache = <String, (DateTime, _EpubBook)>{};

_EpubBook _openEpub(File file) {
  final modified = file.statSync().modified;
  final cached = _epubCache[file.path];
  if (cached != null && cached.$1 == modified) return cached.$2;
  final book = _parseEpub(file.readAsBytesSync());
  if (_epubCache.length >= 8) _epubCache.remove(_epubCache.keys.first);
  _epubCache[file.path] = (modified, book);
  return book;
}

String _resolve(String baseDir, String href) {
  final parts = <String>[];
  for (final p in '$baseDir${Uri.decodeFull(href.split('#').first)}'.split(
    '/',
  )) {
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (p.isNotEmpty && p != '.') {
      parts.add(p);
    }
  }
  return parts.join('/');
}

String _dirOf(String path) =>
    path.contains('/') ? path.substring(0, path.lastIndexOf('/') + 1) : '';

String? _attr(String tag, String name) =>
    RegExp('\\b$name="([^"]*)"').firstMatch(tag)?.group(1);

String _plain(String html) => _htmlToText(
  html,
).replaceAll('#', '').replaceAll(RegExp(r'\s+'), ' ').trim();

_EpubBook _parseEpub(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  List<int>? raw(String path) => zip.findFile(path)?.content as List<int>?;
  String? read(String path) {
    final b = raw(path);
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  final opfPath = RegExp(
    r'full-path="([^"]+)"',
  ).firstMatch(read('META-INF/container.xml') ?? '')?.group(1);
  final opf = opfPath == null ? null : read(opfPath);
  if (opf == null)
    return _EpubBook([_EpubChapter('Tomo', _epubToText(bytes))], null, 'jpeg');
  final dir = _dirOf(opfPath!);

  // Manifiesto: id -> (ruta, tipo, propiedades).
  final manifest = <String, (String, String, String)>{};
  for (final m in RegExp(r'<item\b[^>]*>').allMatches(opf)) {
    final tag = m.group(0)!;
    final id = _attr(tag, 'id'), href = _attr(tag, 'href');
    if (id == null || href == null) continue;
    manifest[id] = (
      _resolve(dir, href),
      _attr(tag, 'media-type') ?? '',
      _attr(tag, 'properties') ?? '',
    );
  }

  // Portada.
  String? coverPath;
  for (final item in manifest.values) {
    if (item.$3.contains('cover-image')) coverPath = item.$1;
  }
  if (coverPath == null) {
    for (final m in RegExp(r'<meta\b[^>]*>').allMatches(opf)) {
      final tag = m.group(0)!;
      if (_attr(tag, 'name') == 'cover')
        coverPath = manifest[_attr(tag, 'content')]?.$1;
    }
  }
  coverPath ??= manifest.entries
      .where(
        (e) =>
            e.value.$2.startsWith('image/') &&
            '${e.key} ${e.value.$1}'.toLowerCase().contains('cover'),
      )
      .firstOrNull
      ?.value
      .$1;
  final coverBytes = coverPath == null ? null : raw(coverPath);
  final coverType = coverPath == null
      ? 'jpeg'
      : (_ext(coverPath) == '.png' ? 'png' : 'jpeg');

  // Lectura en orden (spine).
  final spine = <String>[
    for (final m in RegExp(r'<itemref\b[^>]*\bidref="([^"]+)"').allMatches(opf))
      if (manifest[m.group(1)] case final item? when !item.$3.contains('nav'))
        item.$1,
  ];

  // Índice: nav.xhtml (EPUB 3) o toc.ncx (EPUB 2). Entradas (título, documento).
  final toc = <(String, String)>[];
  final nav = manifest.values.where((i) => i.$3.contains('nav')).firstOrNull;
  if (nav != null) {
    final html = read(nav.$1) ?? '';
    final block =
        RegExp(
          r'<nav\b[^>]*toc[^>]*>([\s\S]*?)</nav>',
        ).firstMatch(html)?.group(1) ??
        html;
    for (final a in RegExp(
      r'<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
    ).allMatches(block)) {
      toc.add((_plain(a.group(2)!), _resolve(_dirOf(nav.$1), a.group(1)!)));
    }
  }
  if (toc.isEmpty) {
    final ncx = manifest.values
        .where((i) => i.$2.contains('dtbncx'))
        .firstOrNull;
    final xml = ncx == null ? '' : read(ncx.$1) ?? '';
    for (final m in RegExp(
      r'<text>([\s\S]*?)</text>[\s\S]*?<content\b[^>]*src="([^"]+)"',
    ).allMatches(xml)) {
      toc.add((_plain(m.group(1)!), _resolve(_dirOf(ncx!.$1), m.group(2)!)));
    }
  }

  String docText(int i) => _htmlToText(read(spine[i]) ?? '');
  final chapters = <_EpubChapter>[];
  // Inicio de cada capítulo en el spine (la primera entrada del índice que apunte a cada documento).
  final starts = <int, String>{};
  for (final (title, path) in toc) {
    final i = spine.indexOf(path);
    if (i >= 0 && !starts.containsKey(i) && title.isNotEmpty) starts[i] = title;
  }
  final ordered = starts.keys.toList()..sort();
  if (ordered.isNotEmpty) {
    for (var k = 0; k < ordered.length; k++) {
      final end = k + 1 < ordered.length ? ordered[k + 1] : spine.length;
      final text = [
        for (var i = ordered[k]; i < end; i++) docText(i),
      ].where((t) => t.isNotEmpty).join('\n\n');
      if (text.trim().isNotEmpty)
        chapters.add(_EpubChapter(starts[ordered[k]]!, text));
    }
  } else {
    // Sin índice: un capítulo por documento con texto.
    for (var i = 0; i < spine.length; i++) {
      final text = docText(i);
      if (text.trim().isEmpty) continue;
      final heading = RegExp(
        r'^# (.+)$',
        multiLine: true,
      ).firstMatch(text)?.group(1);
      chapters.add(
        _EpubChapter(heading ?? 'Parte ${chapters.length + 1}', text),
      );
    }
  }
  if (chapters.isEmpty) chapters.add(_EpubChapter('Tomo', _epubToText(bytes)));
  return _EpubBook(chapters, coverBytes, coverType);
}

int? _firstNumber(String s) =>
    int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '');

/// Rutas de tomos (devuelve false si no es una de ellas).
Future<bool> _novelVolumes(HttpRequest req, Map<String, String> q) async {
  switch (req.uri.path) {
    case '/novels/volumes':
      final work = _workDir(q['lib'], q['work']);
      if (work == null) {
        _json(req, 404, {'error': 'not found'});
        return true;
      }
      _json(req, 200, {
        'volumes': [
          for (final f in _volumeFiles(work))
            () {
              final name = _baseName(f.path);
              var chapters = 0;
              var cover = _volumeSidecarCover(f) != null;
              try {
                final book = _openEpub(f);
                chapters = book.chapters.length;
                cover = cover || book.cover != null;
              } catch (_) {}
              return {
                'id': name,
                'title': _stem(name),
                'number': _firstNumber(_stem(name)),
                'chapters': chapters,
                'hasCover': cover,
                'updatedAt': f.statSync().modified.millisecondsSinceEpoch,
              };
            }(),
        ],
      });
      return true;

    case '/novels/volcover':
      final work = _workDir(q['lib'], q['work']);
      final file = work == null ? null : _volumeFile(work, q['vol']);
      if (file == null) {
        _json(req, 404, {'error': 'not found'});
        return true;
      }
      final sidecar = _volumeSidecarCover(file);
      List<int>? bytes;
      var type = 'jpeg';
      if (sidecar != null) {
        bytes = await sidecar.readAsBytes();
        type = _ext(sidecar.path) == '.png'
            ? 'png'
            : (_ext(sidecar.path) == '.webp' ? 'webp' : 'jpeg');
      } else {
        try {
          final book = _openEpub(file);
          bytes = book.cover;
          type = book.coverType;
        } catch (_) {}
      }
      if (bytes == null) {
        _json(req, 404, {'error': 'no cover'});
        return true;
      }
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('image', type)
        ..headers.set('Cache-Control', 'private, max-age=86400')
        ..add(bytes);
      await req.response.close();
      return true;
  }
  return false;
}

/// Capítulos de un tomo para /novels/chapters?vol=.
List<Map<String, Object?>> _volumeChapters(Directory work, String vol) {
  final file = _volumeFile(work, vol);
  if (file == null) return const [];
  final book = _openEpub(file);
  return [
    for (final (i, c) in book.chapters.indexed)
      {
        'id': '$vol#$i',
        'title': c.title,
        'number': i + 1,
        'volume': _stem(vol),
        'size': c.text.length,
      },
  ];
}

/// Texto de "<tomo>#<n>" (null si no existe).
String? _volumeChapterText(Directory work, String ch) {
  final hash = ch.lastIndexOf('#');
  if (hash < 0) return null;
  final file = _volumeFile(work, ch.substring(0, hash));
  final index = int.tryParse(ch.substring(hash + 1));
  if (file == null || index == null) return null;
  final chapters = _openEpub(file).chapters;
  return index >= 0 && index < chapters.length ? chapters[index].text : null;
}

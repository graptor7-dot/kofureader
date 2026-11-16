import 'models.dart';

// Separar los capítulos extra (omakes, ilustraciones, avisos, extras de tomo…) de la historia,
// sin confundirlos con las partes de un capítulo (12.1, «Part 2», «Segunda parte»).
// Las reglas salen del análisis de la biblioteca real: ver docs/lector-extras.md.

enum ChapterKind {
  story, // capítulo normal
  part, // parte de un capítulo (X.1, «Part 2»…): es historia
  extra, // extra seguro
  probableExtra; // decimal muy corto sin pistas: probablemente extra

  bool get isExtra => this == extra || this == probableExtra;
}

/// Nombre de un capítulo ya limpio: número y título.
class ParsedChapter {
  final double? number;
  final String title;
  final bool exPrefix; // MANGA Plus «ex - …»

  const ParsedChapter(this.number, this.title, this.exPrefix);

  /// Parte decimal del número (0 si es entero o no tiene).
  double get fraction => number == null ? 0 : number! - number!.floorToDouble();
  bool get isDecimal => fraction > 0.0001;
  int? get whole => number?.floor();
}

final _groupPrefix = RegExp(
  r'^.*?_\s*(?=(chapter|ch\.|cap|ex(?![\p{L}])|#|episode|ep\.))',
  caseSensitive: false,
  unicode: true,
);
final _exPrefix = RegExp(r'^ex(?![\p{L}\d])\s*[-–—:_.]*\s*', caseSensitive: false, unicode: true);
final _keywordNumber = RegExp(
  r'(?<![\p{L}])(chapter|cap[ií]tulo|cap\.?|ch\.?|episode|ep\.?|#)\s*(\d+(?:[.,]\d+)?)',
  caseSensitive: false,
  unicode: true,
);
final _trailingNumber = RegExp(r'(\d+(?:[.,]\d+)?)\s*$');
final _groupTag = RegExp(r'\(([^\s()]+)\)');

/// Lee el nombre del fichero (y el título de ComicInfo, si lo hay).
ParsedChapter parseChapterName(String name, {String? metaTitle}) {
  var s = name.replaceFirst(RegExp(r'\.(cbz|cbr|cb7|zip|rar|pdf|epub)$', caseSensitive: false), '');
  s = s.replaceFirst(_groupPrefix, '').trim();
  final ex = _exPrefix.hasMatch(s);
  double? number;
  var title = '';
  if (ex) {
    title = s.replaceFirst(_exPrefix, ''); // los «ex» de MANGA Plus no tienen número
  } else if (_keywordNumber.firstMatch(s) case final m?) {
    number = double.tryParse(m.group(2)!.replaceAll(',', '.'));
    title = s.substring(m.end);
  } else if (_trailingNumber.firstMatch(s) case final m?) {
    number = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    title = s.substring(0, m.start);
    if (title.contains('_')) title = title.substring(title.lastIndexOf('_') + 1);
    title = ''; // «Official_Mischief 100»: lo de delante es la obra, no un título
  } else {
    title = s;
  }
  title = _cleanTitle(title);
  // ComicInfo: si Komga tiene un título propio (distinto del nombre del fichero), también cuenta.
  if (metaTitle != null && metaTitle.trim() != name.trim()) {
    final t = _cleanTitle(metaTitle);
    if (title.isEmpty) title = t;
  }
  return ParsedChapter(number, title, ex);
}

String _cleanTitle(String t) {
  var s = t.replaceAll('_', ' ');
  // Etiquetas de grupo entre paréntesis: «(1r0n)», «(Official)». Se dejan «(2)» y las de «parte».
  s = s.replaceAllMapped(_groupTag, (m) {
    final inner = m.group(1)!;
    if (RegExp(r'^\d+$').hasMatch(inner) || RegExp(r'part', caseSensitive: false).hasMatch(inner)) {
      return m.group(0)!;
    }
    return ' ';
  });
  s = s.replaceFirst(RegExp(r'^[\s\-–—:.,]+'), '');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _labelStart =
    r'(extras?|bonus|omake|illustrations?|twitter extra|side ?story|after ?story|afterword|notice|aviso|anuncio|'
    r'announcement|hiatus|gallery|character (?:profiles?|designs?)|vol(?:ume|\.)? ?\d+ extras?|'
    r'extras? del volumen ?\d+|tomo ?\d+ extras?|special chapter|extra chapter|bonus chapter|extra edition|'
    r'cap[ií]tulo especial|one[ -]?shot)';
final _startsWithLabel = RegExp('^$_labelStart(?![\\p{L}\\d])', caseSensitive: false, unicode: true);
final _containsExpression = RegExp(
  r'(?<![\p{L}])(twitter extra|vol(?:ume|\.)? ?\d+ extras|bonus chapter|extra chapter|extra edition|omake)(?![\p{L}])',
  caseSensitive: false,
  unicode: true,
);
final _partMarker = RegExp(
  r'(\bpart\.? ?(\d+|[ivx]+|one|two|three|four)\b|\bpt\. ?\d+|\(\d+\)|\(?(primera|segunda|tercera|cuarta|quinta) parte\)?)',
  caseSensitive: false,
);

String _normalizeTitle(String t) =>
    t.replaceAll(_partMarker, ' ').toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

/// Clasifica todos los capítulos de una serie (las reglas miran a los vecinos).
/// [override] devuelve la corrección manual ('extra' o 'story') si la hay.
Map<String, ChapterKind> classifyChapters(List<KomgaBook> books, {String? Function(KomgaBook b)? override}) {
  final parsed = {for (final b in books) b.id: parseChapterName(b.name, metaTitle: b.title)};
  final wholeTitles = <int, String>{}; // capítulo entero X -> título normalizado
  final decimalsOf = <int, int>{}; // X -> cuántos X.y hay
  for (final p in parsed.values) {
    final w = p.whole;
    if (w == null) continue;
    if (p.isDecimal) {
      decimalsOf[w] = (decimalsOf[w] ?? 0) + 1;
    } else {
      wholeTitles[w] = _normalizeTitle(p.title);
    }
  }
  final pages = [for (final b in books) b.pagesCount]..sort();
  final median = pages.isEmpty ? 0 : pages[pages.length ~/ 2];

  ChapterKind classify(KomgaBook b) {
    switch (override?.call(b)) {
      case 'extra':
        return ChapterKind.extra;
      case 'story':
        return ChapterKind.story;
    }
    final p = parsed[b.id]!;
    final title = p.title;
    // A. Extra seguro.
    if (p.number == null && (p.exPrefix || _startsWithLabel.hasMatch(title))) return ChapterKind.extra;
    if (_startsWithLabel.hasMatch(title) || _containsExpression.hasMatch(title)) return ChapterKind.extra;
    if (!p.isDecimal) return ChapterKind.story; // D. Normal
    final whole = p.whole!;
    // B. Parte de un capítulo.
    if (_partMarker.hasMatch(title)) return ChapterKind.part;
    final wholeTitle = wholeTitles[whole];
    if (wholeTitle != null && wholeTitle.isNotEmpty && wholeTitle == _normalizeTitle(title)) return ChapterKind.part;
    if (wholeTitle == null && (decimalsOf[whole] ?? 0) >= 2) return ChapterKind.part;
    // C. Decimal sin pistas.
    final fraction = p.fraction;
    if (fraction < 0.45) return ChapterKind.part;
    final short = b.pagesCount > 0 && (b.pagesCount <= 8 || b.pagesCount < median * 0.35);
    return short ? ChapterKind.probableExtra : ChapterKind.story;
  }

  final result = {for (final b in books) b.id: classify(b)};
  for (final b in books) {
    _kinds[b] = result[b.id];
    _parsed[b] = parsed[b.id];
  }
  return result;
}

final _kinds = Expando<ChapterKind>();
final _parsed = Expando<ParsedChapter>();

/// Clase del capítulo, ya calculada con [classifyChapters] para su serie.
extension ChapterKindOf on KomgaBook {
  ChapterKind get kind => _kinds[this] ?? ChapterKind.story;
  bool get isExtra => kind.isExtra;

  /// Número leído del nombre (p. ej. 40.5), si se ha clasificado.
  double? get parsedNumber => _parsed[this]?.number;
}

/// Clave de la corrección manual de un capítulo (preferencia sincronizada: 'extra' o 'story').
String chapterKindPrefKey(String sourceId, String bookId) => 'chapterkind:$sourceId:$bookId';

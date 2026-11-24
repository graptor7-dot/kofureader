/// Lo que se saca del nombre de un archivo de capítulo, p. ej. «(TM) Love Story 01.5 [EN]»:
/// número, si es un extra (decimal o «EXTRA»), idioma entre corchetes y si es traducción máquina.
class ChapterLabel {
  final double? number; // para ordenar: «01 EXTRA» cuenta como 1.5
  final bool extra; // 01.5 o «01 EXTRA»: va entre el 1 y el 2
  final String? language; // EN, ES… (último corchete de 2 o 3 letras)
  final bool machine; // «(TM)» delante: traducción máquina
  final String base; // nombre sin (TM), número ni corchetes (para nombrar carpetas)

  const ChapterLabel({this.number, this.extra = false, this.language, this.machine = false, required this.base});

  static final _cache = <String, ChapterLabel>{};

  factory ChapterLabel.of(String name) => _cache.putIfAbsent(name, () => _parse(name));

  /// Texto de la pastilla: «#1», «#12» o «#1EX».
  String? get pill {
    final n = number;
    if (n == null) return null;
    return '#${n.floor()}${extra ? 'EX' : ''}';
  }

  static final _tm = RegExp(r'^\s*\(TM\)\s*');
  static final _bracket = RegExp(r'\s*\[([^\[\]]*)\]\s*$');
  static final _extraWord = RegExp(r'[\s_\-]+extra$', caseSensitive: false);
  static final _number = RegExp(r'(^|[\s#_.]|(?<![\d\w])-)(\d+(?:[.,]\d+)?)$');
  static final _lead = RegExp(
    r'[\s\-_#.:,]*(?:\b(?:ch|chap|chapter|cap|capitulo|capítulo|ep|episode|episodio|vol|volume|volumen|part|parte|no|n)\.?)?[\s\-_#.:,]*$',
    caseSensitive: false,
  );

  static ChapterLabel _parse(String raw) {
    var s = raw.trim().replaceFirst(RegExp(r'\.(cbz|cbr|zip|rar|pdf|epub)$', caseSensitive: false), '');
    final machine = _tm.hasMatch(s);
    s = s.replaceFirst(_tm, '');
    String? language;
    for (var m = _bracket.firstMatch(s); m != null; m = _bracket.firstMatch(s)) {
      final code = m.group(1)!.trim();
      if (language == null && RegExp(r'^[A-Za-z]{2,3}$').hasMatch(code)) language = code.toUpperCase();
      s = s.substring(0, m.start);
    }
    s = s.trimRight();
    var extra = false;
    if (_extraWord.hasMatch(s)) {
      extra = true;
      s = s.replaceFirst(_extraWord, '').trimRight();
    }
    double? number;
    final m = _number.firstMatch(s);
    if (m != null) {
      number = double.tryParse(m.group(2)!.replaceAll(',', '.'));
      s = s.substring(0, m.start + m.group(1)!.length);
    }
    if (number != null) {
      if (number != number.floorToDouble()) {
        extra = true;
      } else if (extra) {
        number += 0.5;
      }
    } else {
      extra = false;
    }
    var base = number == null ? s : s.replaceFirst(_lead, '');
    base = base.trim();
    return ChapterLabel(
      number: number,
      extra: extra,
      language: language,
      machine: machine,
      base: base.isEmpty ? s.trim() : base,
    );
  }
}

/// Ordena por el número del nombre (los extras entre su capítulo y el siguiente);
/// los que no tienen número van al final, en su orden.
List<T> sortByChapterNumber<T>(List<T> items, String Function(T) name) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i], ChapterLabel.of(name(items[i])).number)];
  indexed.sort((a, b) {
    final x = a.$3, y = b.$3;
    if (x == null && y == null) return a.$1.compareTo(b.$1);
    if (x == null) return 1;
    if (y == null) return -1;
    final c = x.compareTo(y);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

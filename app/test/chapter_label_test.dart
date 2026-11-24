import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/data/chapter_label.dart';

void main() {
  test('número e idioma', () {
    final l = ChapterLabel.of('Love Story 01 [EN]');
    expect(l.number, 1);
    expect(l.extra, false);
    expect(l.language, 'EN');
    expect(l.machine, false);
    expect(l.base, 'Love Story');
    expect(l.pill, '#1');
  });

  test('sin idioma', () {
    final l = ChapterLabel.of('Love Story 12');
    expect(l.number, 12);
    expect(l.language, null);
    expect(l.base, 'Love Story');
  });

  test('extras', () {
    final a = ChapterLabel.of('Love Story 01.5 [ES]');
    expect(a.extra, true);
    expect(a.pill, '#1EX');
    expect(a.language, 'ES');
    final b = ChapterLabel.of('Love Story 01 EXTRA');
    expect(b.extra, true);
    expect(b.number, 1.5);
    expect(b.pill, '#1EX');
    expect(b.base, 'Love Story');
  });

  test('traducción máquina y varios corchetes', () {
    final l = ChapterLabel.of('(TM) Love Story 03 [Digital] [EN]');
    expect(l.machine, true);
    expect(l.language, 'EN');
    expect(l.number, 3);
    expect(l.base, 'Love Story');
  });

  test('palabras de capítulo antes del número', () {
    expect(ChapterLabel.of('Love Story - Ch. 04 [EN]').base, 'Love Story');
    expect(ChapterLabel.of('Sin numero [EN]').number, null);
    expect(ChapterLabel.of('Sin numero [EN]').base, 'Sin numero');
    expect(ChapterLabel.of('Sin numero').pill, null);
  });

  test('orden', () {
    final names = ['A 2 [EN]', 'A 1 EXTRA', 'Sin número', 'A 1 [EN]', 'A 10', 'A 1.5'];
    expect(sortByChapterNumber(names, (s) => s), ['A 1 [EN]', 'A 1 EXTRA', 'A 1.5', 'A 2 [EN]', 'A 10', 'Sin número']);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/komga/chapter_kind.dart';
import 'package:kofu_reader/komga/models.dart';

KomgaBook _book(String name, {int pages = 40}) => KomgaBook(
  id: name,
  seriesId: 's',
  seriesTitle: 'Serie',
  libraryId: 'l',
  title: name,
  name: name,
  number: '0',
  pagesCount: pages,
  readProgress: null,
);

/// Clasifica un capítulo dentro de una serie con capítulos normales de 40 páginas alrededor.
ChapterKind _kind(String name, {int pages = 40, List<String> others = const []}) {
  final books = [
    for (var i = 1; i <= 6; i++) _book('Chapter ${i + 200}', pages: 40),
    for (final o in others) _book(o),
    _book(name, pages: pages),
  ];
  return classifyChapters(books)[name]!;
}

void main() {
  test('casos de la biblioteca real', () {
    expect(_kind('Chapter 13.5_ Extras.cbz'), ChapterKind.extra);
    expect(_kind('Chapter 28.5_ Extras del Volumen 3.cbz'), ChapterKind.extra);
    expect(_kind('Chapter 32.5_ Aviso.cbz'), ChapterKind.extra);
    expect(_kind("Senko-san's Abode_Chapter 5.5_ Volume 1 Extras.cbz"), ChapterKind.extra);
    expect(_kind('Chapter 28.5_ Twitter extra - Merry Christmas.cbz'), ChapterKind.extra);
    expect(_kind('MANGA Plus_ex - ILLUSTRATION.cbz'), ChapterKind.extra);
    expect(_kind('MANGA Plus_ex - Capítulo especial 1.cbz'), ChapterKind.extra);
    expect(_kind('Chapter 21.6_ Case. 21.6 TENGA①.cbz', pages: 4), ChapterKind.probableExtra);
    expect(_kind('Chapter 19.5_ Piedra Mágica (Segunda parte).cbz'), ChapterKind.part);
    expect(_kind('Chapter 73.1_ Mother, Daughter, and Slave — Part II.cbz'), ChapterKind.part);
    expect(_kind('Chapter 56.1_ (2) The Limit.cbz'), ChapterKind.part);
    expect(_kind('Seven Seas Entertainment_Chapter 10.1_ (1r0n).cbz'), ChapterKind.part);
    expect(_kind('Chapter 7.5_ Official.cbz', pages: 38), ChapterKind.story);
    expect(_kind('Chapter 32_ Special Time.cbz'), ChapterKind.story);
    expect(_kind('Extra Innings Scanlation_Chapter 3_ Manager.cbz'), ChapterKind.story);
    expect(_kind('Chapter 136_ Entrega especial.cbz'), ChapterKind.story);
    expect(_kind('Official_Mischief 100.cbz'), ChapterKind.story);
    expect(_kind('Chapter 0_ Volume 2 extras.cbz'), ChapterKind.extra);
  });

  test('una parte con el mismo título que su capítulo entero es historia', () {
    expect(
      _kind(
        'Chapter 22.5_ Case.22 The Magic Doctor (Part Two)',
        others: ['Chapter 22_ Case.22 The Magic Doctor (Part One)'],
      ),
      ChapterKind.part,
    );
  });

  test('lee el número', () {
    expect(parseChapterName('MANGA Plus_#139 - Mission_ 139').number, 139);
    expect(parseChapterName('Official_Mischief 100').number, 100);
    expect(parseChapterName('Violet Scans_Chapter 40.5').number, 40.5);
    expect(parseChapterName('MANGA Plus_ex - Illustration').number, isNull);
  });

  test('la corrección manual gana', () {
    final b = _book('Chapter 13.5_ Extras');
    expect(classifyChapters([b], override: (_) => 'story')[b.id], ChapterKind.story);
  });
}

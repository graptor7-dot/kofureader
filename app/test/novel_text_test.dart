import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/ui/novels/novel_reader_screen.dart';

void main() {
  test('párrafos separados por líneas en blanco', () {
    final b = parseNovelText('Hola.\nSigue aquí.\n\nOtro párrafo.\r\n\r\n***\n\n# Título\n\nFin **fuerte**.');
    expect(b.map((x) => x.separator ? '---' : (x.heading ? 'H:${x.text}' : x.text)).toList(), [
      'Hola.\nSigue aquí.',
      'Otro párrafo.',
      '---',
      'H:Título',
      'Fin fuerte.',
    ]);
  });

  test('sin líneas en blanco, cada línea es un párrafo', () {
    expect(parseNovelText('Uno\nDos\nTres').map((x) => x.text).toList(), ['Uno', 'Dos', 'Tres']);
  });
}
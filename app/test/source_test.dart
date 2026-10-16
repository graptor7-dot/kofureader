import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/data/source.dart';

void main() {
  group('Source.normalizeUrl', () {
    test('quita /dashboard y la barra final', () {
      expect(Source.normalizeUrl('https://manga.example.com/dashboard'), 'https://manga.example.com');
      expect(Source.normalizeUrl('https://manga.example.com/'), 'https://manga.example.com');
    });

    test('conserva puerto y esquema http', () {
      expect(Source.normalizeUrl('http://100.64.0.10:49158/dashboard'), 'http://100.64.0.10:49158');
    });

    test('añade https si falta el esquema', () {
      expect(Source.normalizeUrl('manga.example.com'), 'https://manga.example.com');
    });

    test('conserva un subdirectorio', () {
      expect(Source.normalizeUrl('https://example.com/komga/libraries/abc'), 'https://example.com/komga');
    });
  });
}

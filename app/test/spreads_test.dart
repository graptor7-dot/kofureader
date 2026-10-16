import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/komga/models.dart';
import 'package:kofu_reader/ui/reader/reader_screen.dart';

KomgaPageInfo _p(int n, {bool wide = false}) => KomgaPageInfo(n, wide ? 2000 : 1000, 1400);

void main() {
  test('sin doble página: una página por vista', () {
    expect(buildSpreads([_p(1), _p(2), _p(3)], spreads: false), [
      [0],
      [1],
      [2],
    ]);
  });

  test('portada sola y el resto por parejas', () {
    expect(buildSpreads([_p(1), _p(2), _p(3), _p(4), _p(5)], spreads: true), [
      [0],
      [1, 2],
      [3, 4],
    ]);
  });

  test('las páginas anchas van solas y la última suelta también', () {
    final pages = [_p(1), _p(2), _p(3, wide: true), _p(4), _p(5), _p(6)];
    expect(buildSpreads(pages, spreads: true), [
      [0],
      [1],
      [2],
      [3, 4],
      [5],
    ]);
  });
}

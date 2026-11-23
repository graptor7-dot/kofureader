import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/data/comic_tags.dart';

void main() {
  test('las rutas de Komga y KofuSync se emparejan por carpeta y archivo', () {
    expect(
      ComicTagIndex.pathKey('/data/privado/Mangas/2no/Until the Nasty Rain is Over [EN].cbz'),
      ComicTagIndex.pathKey('2no/Until the Nasty Rain is Over [EN].cbz'),
    );
    expect(ComicTagIndex.pathKey(r'C:\Mangas\Abubu\X.cbz'), 'abubu/x.cbz');
  });
}

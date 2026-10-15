import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/data/source.dart';
import 'package:kofu_reader/data/user_data.dart';

Source _src(String id, String url) => Source(id: id, name: id, baseUrl: url, authType: AuthType.apiKey);

ItemSnapshot _series(String sourceId, String id) =>
    ItemSnapshot(ref: ItemRef(sourceId, ItemKind.series, id), title: id, libraryId: 'lib');

/// Simula un viaje al servidor: lo que un dispositivo sube, el otro lo recibe.
void _transfer(UserData from, UserData to) => to.applyRemote(from.changesSince(0));

void main() {
  test('una lista creada en un dispositivo llega al otro', () {
    final pc = UserData();
    final ipad = UserData();
    final list = pc.createList('Para leer');
    pc.addAll(list.id, [_series('S', 'a')]);
    _transfer(pc, ipad);
    expect(ipad.customLists.single.name, 'Para leer');
    expect(ipad.itemsOf(list.id).single.item.ref.komgaId, 'a');
  });

  test('gana el cambio más reciente y los borrados se propagan', () async {
    final pc = UserData();
    final ipad = UserData();
    final list = pc.createList('Uno');
    _transfer(pc, ipad);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ipad.renameList(list.id, 'Renombrada');
    _transfer(ipad, pc);
    expect(pc.list(list.id)!.name, 'Renombrada');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    pc.deleteList(list.id);
    _transfer(pc, ipad);
    expect(ipad.list(list.id), isNull);
  });

  test('el mismo Komga dado de alta en dos dispositivos se fusiona', () async {
    final pc = UserData();
    pc.upsertSource(_src('pc-id', 'http://komga:1'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final ipad = UserData();
    ipad.upsertSource(_src('ipad-id', 'http://komga:1'));
    ipad.addAll(UserData.favoritesId, [_series('ipad-id', 'x')]);
    ipad.setPref('seriesmode:ipad-id:x', 'vertical');

    String? remapped;
    ipad.onSourceRemapped = (o, n) => remapped = '$o->$n';
    _transfer(pc, ipad); // el del PC es más antiguo: el iPad adopta su id
    expect(remapped, 'ipad-id->pc-id');
    expect(ipad.sources.map((s) => s.id), ['pc-id']);
    expect(ipad.isFavorite(ItemRef('pc-id', ItemKind.series, 'x')), isTrue);
    expect(ipad.pref('seriesmode:pc-id:x'), 'vertical');

    _transfer(ipad, pc); // y el PC no acaba con un duplicado
    expect(pc.sources.map((s) => s.id), ['pc-id']);
    expect(pc.isFavorite(ItemRef('pc-id', ItemKind.series, 'x')), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/data/chapter_groups.dart';
import 'package:kofu_reader/data/user_data.dart';

void main() {
  test('crear, mover, portada y deshacer agrupaciones', () {
    final data = UserData();
    final groups = ChapterGroups(data, 'src', 'autor');
    expect(groups.all, isEmpty);

    final a = groups.create('Miniserie A', ['b1', 'b2', 'b3']);
    final b = groups.create('Miniserie B', ['b3', 'b4']); // b3 se mueve de A a B
    expect(groups.byId(a.id)!.bookIds, ['b1', 'b2']);
    expect(groups.byBook['b3']!.id, b.id);

    groups.addTo(a.id, ['b4']);
    expect(groups.byId(b.id)!.bookIds, ['b3']);
    expect(groups.byId(a.id)!.bookIds, ['b1', 'b2', 'b4']);

    // Portada: la elegida si sigue dentro; si no, la del primer libro.
    expect(groups.byId(a.id)!.coverIn(['b1', 'b2', 'b4']), 'b1');
    groups.update(groups.byId(a.id)!.copyWith(coverBookId: 'b4', name: 'A'));
    expect(groups.byId(a.id)!.coverIn(['b1', 'b2', 'b4']), 'b4');
    expect(groups.byId(a.id)!.name, 'A');

    // Una agrupación vacía desaparece.
    groups.removeBooks(['b3']);
    expect(groups.byId(b.id), isNull);

    groups.dissolve(a.id);
    expect(groups.all, isEmpty);
    expect(data.pref(chapterGroupsPrefKey('src', 'autor')), isNull);
  });
}

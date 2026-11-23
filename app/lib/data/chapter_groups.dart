import 'dart:convert';

import 'user_data.dart';

/// Agrupación de libros dentro de una serie (p. ej. una miniserie de un autor).
/// Se guarda como preferencia sincronizada, así se ve igual en todos los dispositivos.
class ChapterGroup {
  final String id;
  final String name;
  final String? coverBookId; // libro cuya portada se usa; si no, el primero
  final List<String> bookIds;

  const ChapterGroup({required this.id, required this.name, this.coverBookId, required this.bookIds});

  ChapterGroup copyWith({String? name, String? coverBookId, List<String>? bookIds}) => ChapterGroup(
    id: id,
    name: name ?? this.name,
    coverBookId: coverBookId ?? this.coverBookId,
    bookIds: bookIds ?? this.bookIds,
  );

  /// Libro de portada: el elegido si sigue en la agrupación; si no, el primero de [inOrder].
  String? coverIn(List<String> inOrder) {
    if (coverBookId != null && bookIds.contains(coverBookId)) return coverBookId;
    return inOrder.where(bookIds.contains).firstOrNull ?? bookIds.firstOrNull;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'cover': ?coverBookId, 'books': bookIds};

  static ChapterGroup? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], books = j['books'];
    if (id is! String || name is! String || books is! List) return null;
    return ChapterGroup(
      id: id,
      name: name,
      coverBookId: j['cover'] as String?,
      bookIds: books.whereType<String>().toList(),
    );
  }
}

String chapterGroupsPrefKey(String sourceId, String seriesId) => 'groups:$sourceId:$seriesId';

/// Lee y guarda las agrupaciones de una serie.
class ChapterGroups {
  final UserData data;
  final String sourceId;
  final String seriesId;

  ChapterGroups(this.data, this.sourceId, this.seriesId);

  String get _key => chapterGroupsPrefKey(sourceId, seriesId);

  List<ChapterGroup> get all {
    final raw = data.pref(_key);
    if (raw == null) return const [];
    try {
      return [for (final g in jsonDecode(raw) as List) ?ChapterGroup.fromJson(g)];
    } catch (_) {
      return const [];
    }
  }

  ChapterGroup? byId(String id) => all.where((g) => g.id == id).firstOrNull;

  /// Agrupación a la que pertenece cada libro.
  Map<String, ChapterGroup> get byBook => {
    for (final g in all)
      for (final b in g.bookIds) b: g,
  };

  void _save(List<ChapterGroup> groups) {
    final kept = groups.where((g) => g.bookIds.isNotEmpty).toList();
    data.setPref(_key, kept.isEmpty ? null : jsonEncode([for (final g in kept) g.toJson()]));
  }

  /// Crea una agrupación con estos libros (los saca de la que tuvieran).
  ChapterGroup create(String name, List<String> bookIds) {
    final g = ChapterGroup(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), name: name, bookIds: bookIds);
    _save([..._without(bookIds), g]);
    return g;
  }

  /// Mete libros en una agrupación existente (los saca de la que tuvieran).
  void addTo(String groupId, List<String> bookIds) {
    _save([
      for (final g in _without(bookIds)) g.id == groupId ? g.copyWith(bookIds: [...g.bookIds, ...bookIds]) : g,
    ]);
  }

  void removeBooks(List<String> bookIds) => _save(_without(bookIds));

  void update(ChapterGroup group) => _save([for (final g in all) g.id == group.id ? group : g]);

  void dissolve(String groupId) => _save(all.where((g) => g.id != groupId).toList());

  List<ChapterGroup> _without(List<String> bookIds) => [
    for (final g in all) g.copyWith(bookIds: g.bookIds.where((b) => !bookIds.contains(b)).toList()),
  ];
}

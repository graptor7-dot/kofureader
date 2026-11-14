import 'dart:convert';
import 'dart:ui' show Color;

import 'package:uuid/uuid.dart';

import 'app_state.dart';
import 'user_data.dart';

/// Etiqueta creada por el usuario.
class UserTag {
  final String id;
  final String name;
  final int color;

  UserTag(this.id, this.name, this.color);

  Color get colorValue => Color(color);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
  factory UserTag.fromJson(Map<String, dynamic> j) =>
      UserTag(j['id'] as String, j['name'] as String, j['color'] as int);
}

/// Una página guardada.
class Bookmark {
  final ItemSnapshot book;
  final int page;
  final int createdAt;

  Bookmark(this.book, this.page, this.createdAt);

  String get key => '${book.ref.key}|$page';
}

/// Secciones del inicio (se pueden reordenar u ocultar).
enum HomeSection {
  continueReading('Seguir leyendo'),
  upNext('Te toca'),
  shortcuts('Atajos'),
  libraries('Bibliotecas'),
  complete('Ediciones completas'),
  lists('Listas');

  final String label;
  const HomeSection(this.label);
}

/// Valoraciones, etiquetas, marcadores, Top 10 y orden del inicio.
///
/// Todo se guarda como preferencias sincronizadas de [UserData] (con borrado
/// lógico), así que funciona igual en todos los dispositivos.
class Extras {
  final AppState state;

  Extras(this.state);

  UserData get _data => state.data;

  Map<String, dynamic>? _json(String key) {
    final v = _data.pref(key);
    if (v == null) return null;
    try {
      return jsonDecode(v) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ---- Valoración (1..5) ----

  int rating(ItemRef ref) => (_json('rating:${ref.key}')?['r'] as int?) ?? 0;

  void setRating(ItemSnapshot item, int stars) =>
      _data.setPref('rating:${item.ref.key}', stars <= 0 ? null : jsonEncode({'r': stars, 's': item.toJson()}));

  /// Obras valoradas de una biblioteca, de más a menos estrellas.
  List<(ItemSnapshot, int)> rated({String? sourceId, String? libraryId, ItemKind? kind}) {
    final out = <(ItemSnapshot, int)>[];
    for (final k in _data.prefKeys.where((k) => k.startsWith('rating:'))) {
      final j = _json(k);
      if (j == null) continue;
      final s = ItemSnapshot.fromJson((j['s'] as Map).cast<String, dynamic>());
      if (sourceId != null && s.ref.sourceId != sourceId) continue;
      if (libraryId != null && s.libraryId != libraryId) continue;
      if (kind != null && s.ref.kind != kind) continue;
      out.add((s, j['r'] as int));
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  // ---- Etiquetas ----

  static const tagColors = [
    0xFFFF5D8F,
    0xFF8C6BFF,
    0xFF38BDF8,
    0xFF34D399,
    0xFFF59E0B,
    0xFFF97316,
    0xFFEF4444,
    0xFFA3E635,
  ];

  List<UserTag> get tags {
    final v = _data.pref('tags');
    if (v == null) return [];
    try {
      return [for (final t in (jsonDecode(v) as List).cast<Map<String, dynamic>>()) UserTag.fromJson(t)];
    } catch (_) {
      return [];
    }
  }

  void _saveTags(List<UserTag> tags) => _data.setPref('tags', jsonEncode([for (final t in tags) t.toJson()]));

  UserTag createTag(String name) {
    final list = tags;
    final tag = UserTag(const Uuid().v4(), name.trim(), tagColors[list.length % tagColors.length]);
    _saveTags([...list, tag]);
    return tag;
  }

  void renameTag(String id, String name) =>
      _saveTags([for (final t in tags) t.id == id ? UserTag(t.id, name.trim(), t.color) : t]);

  void deleteTag(String id) {
    _saveTags(tags.where((t) => t.id != id).toList());
    for (final k in _data.prefKeys.where((k) => k.startsWith('tag:')).toList()) {
      final j = _json(k);
      final ids = ((j?['t'] as List?) ?? const []).cast<String>().where((t) => t != id).toList();
      _data.setPref(k, ids.isEmpty ? null : jsonEncode({...?j, 't': ids}));
    }
  }

  List<String> tagsOf(ItemRef ref) => ((_json('tag:${ref.key}')?['t'] as List?) ?? const []).cast<String>();

  void setTags(ItemSnapshot item, List<String> tagIds) =>
      _data.setPref('tag:${item.ref.key}', tagIds.isEmpty ? null : jsonEncode({'t': tagIds, 's': item.toJson()}));

  /// Añade o quita una etiqueta a varios elementos.
  void toggleTag(Iterable<ItemSnapshot> items, String tagId, bool add) {
    for (final item in items) {
      final current = tagsOf(item.ref).toSet();
      add ? current.add(tagId) : current.remove(tagId);
      setTags(item, current.toList());
    }
  }

  /// Elementos con una etiqueta (opcionalmente de una biblioteca).
  List<ItemSnapshot> tagged(String tagId, {String? sourceId, String? libraryId}) {
    final out = <ItemSnapshot>[];
    for (final k in _data.prefKeys.where((k) => k.startsWith('tag:'))) {
      final j = _json(k);
      if (j == null || !((j['t'] as List?) ?? const []).contains(tagId)) continue;
      final s = ItemSnapshot.fromJson((j['s'] as Map).cast<String, dynamic>());
      if (sourceId != null && s.ref.sourceId != sourceId) continue;
      if (libraryId != null && s.libraryId != libraryId) continue;
      out.add(s);
    }
    out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return out;
  }

  // ---- Marcadores ----

  bool isBookmarked(ItemRef book, int page) => _data.pref('bm:${book.key}|$page') != null;

  void setBookmark(ItemSnapshot book, int page, bool on) => _data.setPref(
    'bm:${book.ref.key}|$page',
    on ? jsonEncode({'s': book.toJson(), 'p': page, 'at': DateTime.now().millisecondsSinceEpoch}) : null,
  );

  List<Bookmark> get bookmarks {
    final out = <Bookmark>[];
    for (final k in _data.prefKeys.where((k) => k.startsWith('bm:'))) {
      final j = _json(k);
      if (j == null) continue;
      out.add(
        Bookmark(ItemSnapshot.fromJson((j['s'] as Map).cast<String, dynamic>()), j['p'] as int, j['at'] as int? ?? 0),
      );
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  // ---- Top 10 por biblioteca ----

  static const topSize = 10;

  String _topKey(String sourceId, String libraryId) => 'top10:$sourceId:$libraryId';

  List<ItemSnapshot> top10(String sourceId, String libraryId) {
    final v = _data.pref(_topKey(sourceId, libraryId));
    if (v == null) return [];
    try {
      return [for (final s in (jsonDecode(v) as List).cast<Map<String, dynamic>>()) ItemSnapshot.fromJson(s)];
    } catch (_) {
      return [];
    }
  }

  void setTop10(String sourceId, String libraryId, List<ItemSnapshot> items) => _data.setPref(
    _topKey(sourceId, libraryId),
    items.isEmpty ? null : jsonEncode([for (final i in items.take(topSize)) i.toJson()]),
  );

  bool inTop10(ItemSnapshot item) => top10(item.ref.sourceId, item.libraryId).any((i) => i.ref == item.ref);

  /// Bibliotecas que tienen Top 10, como (sourceId, libraryId).
  List<(String, String)> get top10Libraries => [
    for (final k in _data.prefKeys.where((k) => k.startsWith('top10:')))
      if (k.split(':').length >= 3) (k.split(':')[1], k.split(':').sublist(2).join(':')),
  ];

  // ---- Orden del inicio ----

  /// Secciones del inicio en orden, con su visibilidad.
  List<(HomeSection, bool)> get homeLayout {
    final v = _data.pref('home_layout');
    final result = <(HomeSection, bool)>[];
    if (v != null) {
      try {
        for (final e in (jsonDecode(v) as List).cast<Map<String, dynamic>>()) {
          final s = HomeSection.values.asNameMap()[e['id']];
          if (s != null && !result.any((r) => r.$1 == s)) result.add((s, e['on'] != false));
        }
      } catch (_) {}
    }
    for (final s in HomeSection.values) {
      if (!result.any((r) => r.$1 == s)) result.add((s, true));
    }
    return result;
  }

  void setHomeLayout(List<(HomeSection, bool)> layout) => _data.setPref(
    'home_layout',
    jsonEncode([
      for (final (s, on) in layout) {'id': s.name, 'on': on},
    ]),
  );
}

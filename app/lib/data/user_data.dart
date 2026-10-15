import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'source.dart';

/// Qué guarda un elemento de lista.
enum ItemKind { series, book }

/// Referencia a una serie o libro de un servidor concreto.
class ItemRef {
  final String sourceId;
  final ItemKind kind;
  final String komgaId;

  const ItemRef(this.sourceId, this.kind, this.komgaId);

  String get key => '$sourceId|${kind.name}|$komgaId';

  @override
  bool operator ==(Object other) => other is ItemRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Datos de una serie o libro guardados junto a la referencia, para poder
/// pintar la lista sin preguntar a Komga por cada elemento.
class ItemSnapshot {
  final ItemRef ref;
  final String title;
  final String libraryId;
  final String? seriesId; // solo libros
  final String? seriesTitle; // solo libros

  const ItemSnapshot({
    required this.ref,
    required this.title,
    required this.libraryId,
    this.seriesId,
    this.seriesTitle,
  });
}

/// Un servidor Komga con sus metadatos de sincronización.
class SourceRecord {
  final Source source;
  final int createdAt;
  final int updatedAt;
  final bool deleted;

  const SourceRecord(this.source, this.createdAt, this.updatedAt, {this.deleted = false});

  Map<String, dynamic> toJson() => {
    ...source.toJson(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deleted': deleted,
  };

  factory SourceRecord.fromJson(Map<String, dynamic> j) => SourceRecord(
    Source.fromJson(j),
    j['createdAt'] as int? ?? 0,
    j['updatedAt'] as int? ?? 0,
    deleted: j['deleted'] as bool? ?? false,
  );
}

class UserList {
  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final bool deleted;

  const UserList(this.id, this.name, this.createdAt, this.updatedAt, {this.deleted = false});

  bool get isFavorites => id == UserData.favoritesId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deleted': deleted,
  };

  factory UserList.fromJson(Map<String, dynamic> j) => UserList(
    j['id'] as String,
    j['name'] as String,
    j['createdAt'] as int,
    j['updatedAt'] as int,
    deleted: j['deleted'] as bool? ?? false,
  );
}

class ListItem {
  final String listId;
  final ItemSnapshot item;
  final int addedAt;
  final int updatedAt;
  final bool deleted;

  const ListItem(this.listId, this.item, this.addedAt, this.updatedAt, {this.deleted = false});

  /// Id determinista: añadir de nuevo algo borrado reutiliza el mismo registro.
  String get id => '$listId|${item.ref.key}';

  Map<String, dynamic> toJson() => {
    'listId': listId,
    'sourceId': item.ref.sourceId,
    'kind': item.ref.kind.name,
    'komgaId': item.ref.komgaId,
    'title': item.title,
    'libraryId': item.libraryId,
    'seriesId': item.seriesId,
    'seriesTitle': item.seriesTitle,
    'addedAt': addedAt,
    'updatedAt': updatedAt,
    'deleted': deleted,
  };

  factory ListItem.fromJson(Map<String, dynamic> j) => ListItem(
    j['listId'] as String,
    ItemSnapshot(
      ref: ItemRef(j['sourceId'] as String, ItemKind.values.byName(j['kind'] as String), j['komgaId'] as String),
      title: j['title'] as String,
      libraryId: j['libraryId'] as String,
      seriesId: j['seriesId'] as String?,
      seriesTitle: j['seriesTitle'] as String?,
    ),
    j['addedAt'] as int,
    j['updatedAt'] as int,
    deleted: j['deleted'] as bool? ?? false,
  );
}

/// Listas, favoritos y preferencias del usuario.
///
/// Se guardan en un fichero JSON local. Cada registro lleva `updatedAt` y
/// borrado lógico (`deleted`) para poder sincronizarlo más adelante con KofuSync.
class UserData extends ChangeNotifier {
  static const favoritesId = 'favorites';

  final Map<String, UserList> _lists = {};
  final Map<String, ListItem> _items = {};
  final Map<String, ({String? value, int updatedAt})> _prefs = {};
  final Map<String, SourceRecord> _sources = {};

  /// Estado local de la sincronización (no se sincroniza).
  final Map<String, dynamic> syncMeta = {};

  /// True mientras se aplican cambios recibidos del servidor de sincronización.
  bool applyingRemote = false;

  /// Avisa cuando un servidor cambia de id al fusionarse con el de otro dispositivo.
  void Function(String oldId, String newId)? onSourceRemapped;

  File? _file;
  Timer? _saveTimer;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}${Platform.pathSeparator}kofu_data.json');
    if (await _file!.exists()) {
      try {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        for (final l in (j['lists'] as List? ?? [])) {
          final list = UserList.fromJson(l as Map<String, dynamic>);
          _lists[list.id] = list;
        }
        for (final i in (j['items'] as List? ?? [])) {
          final item = ListItem.fromJson(i as Map<String, dynamic>);
          _items[item.id] = item;
        }
        (j['prefs'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
          final m = v as Map<String, dynamic>;
          _prefs[k] = (value: m['value'] as String?, updatedAt: m['updatedAt'] as int);
        });
        for (final s in (j['sources'] as List? ?? [])) {
          final rec = SourceRecord.fromJson(s as Map<String, dynamic>);
          _sources[rec.source.id] = rec;
        }
        syncMeta.addAll((j['sync'] as Map<String, dynamic>? ?? {}));
      } catch (e) {
        debugPrint('No se pudo leer kofu_data.json: $e');
      }
    }
    _lists.putIfAbsent(favoritesId, () => UserList(favoritesId, 'Favoritos', 0, 0));
  }

  void _changed() {
    notifyListeners();
    saveSoon();
  }

  void saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _save);
  }

  // ---- Servidores Komga (sin secretos) ----

  /// Servidores activos, en orden de alta.
  List<Source> get sources =>
      (_sources.values.where((s) => !s.deleted).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
          .map((s) => s.source)
          .toList();

  bool get hasAnySourceRecord => _sources.isNotEmpty;

  void upsertSource(Source source) {
    final now = _now();
    final existing = _sources[source.id];
    _sources[source.id] = SourceRecord(source, existing?.createdAt ?? now, now);
    _changed();
  }

  void deleteSource(String id) {
    final existing = _sources[id];
    if (existing == null) return;
    _sources[id] = SourceRecord(existing.source, existing.createdAt, _now(), deleted: true);
    _changed();
  }

  // ---- Sincronización ----

  /// Registros modificados desde [since] (ms), en el formato de KofuSync.
  List<Map<String, dynamic>> changesSince(int since) => [
    for (final l in _lists.values)
      if (l.updatedAt >= since && l.updatedAt > 0) _record('list', l.id, l.updatedAt, l.deleted, l.toJson()),
    for (final i in _items.values)
      if (i.updatedAt >= since) _record('item', i.id, i.updatedAt, i.deleted, i.toJson()),
    for (final e in _prefs.entries)
      if (e.value.updatedAt >= since)
        _record('pref', e.key, e.value.updatedAt, e.value.value == null, {'value': e.value.value}),
    for (final s in _sources.values)
      if (s.updatedAt >= since) _record('source', s.source.id, s.updatedAt, s.deleted, s.toJson()),
  ];

  static Map<String, dynamic> _record(String type, String id, int updatedAt, bool deleted, Map data) => {
    'type': type,
    'id': id,
    'updatedAt': updatedAt,
    'deleted': deleted,
    'data': data,
  };

  /// Aplica registros recibidos: gana el más reciente.
  void applyRemote(List<dynamic> records) {
    applyingRemote = true;
    try {
      for (final raw in records) {
        try {
          _applyRecord((raw as Map).cast<String, dynamic>());
        } catch (e) {
          // Un registro mal formado no debe bloquear el resto.
          debugPrint('Registro de sincronización ignorado: $e');
        }
      }
      notifyListeners();
    } finally {
      applyingRemote = false;
    }
    saveSoon();
  }

  void _applyRecord(Map<String, dynamic> r) {
    final updatedAt = r['updatedAt'] as int;
    final data = (r['data'] as Map?)?.cast<String, dynamic>();
    if (data == null) return;
    switch (r['type']) {
      case 'list':
        final local = _lists[r['id']];
        if (local == null || local.updatedAt < updatedAt) {
          final l = UserList.fromJson(data);
          _lists[l.id] = l;
        }
      case 'item':
        final local = _items[r['id']];
        if (local == null || local.updatedAt < updatedAt) {
          final i = ListItem.fromJson(data);
          _items[i.id] = i;
        }
      case 'pref':
        final key = r['id'] as String;
        final local = _prefs[key];
        if (local == null || local.updatedAt < updatedAt) {
          _prefs[key] = (value: r['deleted'] == true ? null : data['value'] as String?, updatedAt: updatedAt);
        }
      case 'source':
        _applyRemoteSource(SourceRecord.fromJson(data));
    }
  }

  void _applyRemoteSource(SourceRecord remote) {
    final id = remote.source.id;
    final local = _sources[id];
    if (local != null) {
      if (local.updatedAt < remote.updatedAt) _sources[id] = remote;
      return;
    }
    if (remote.deleted) {
      _sources[id] = remote;
      return;
    }
    // ¿El mismo servidor dado de alta en este dispositivo con otro id?
    final twin = _sources.values.where((s) => !s.deleted && s.source.baseUrl == remote.source.baseUrl).firstOrNull;
    if (twin == null) {
      _sources[id] = remote;
      return;
    }
    // Se queda el más antiguo; el otro dispositivo hará lo mismo al recibir este.
    final remoteWins =
        remote.createdAt < twin.createdAt || (remote.createdAt == twin.createdAt && id.compareTo(twin.source.id) < 0);
    if (remoteWins) {
      _sources[id] = remote;
      _remapSource(twin.source.id, id);
    }
  }

  /// Mueve todo lo que apunta al servidor [oldId] a [newId].
  void _remapSource(String oldId, String newId) {
    final now = _now();
    final old = _sources[oldId]!;
    _sources[oldId] = SourceRecord(old.source, old.createdAt, now, deleted: true);
    for (final item in _items.values.where((i) => i.item.ref.sourceId == oldId && !i.deleted).toList()) {
      _items[item.id] = ListItem(item.listId, item.item, item.addedAt, now, deleted: true);
      final s = item.item;
      final moved = ListItem(
        item.listId,
        ItemSnapshot(
          ref: ItemRef(newId, s.ref.kind, s.ref.komgaId),
          title: s.title,
          libraryId: s.libraryId,
          seriesId: s.seriesId,
          seriesTitle: s.seriesTitle,
        ),
        item.addedAt,
        now,
      );
      final existing = _items[moved.id];
      if (existing == null || existing.deleted) _items[moved.id] = moved;
    }
    for (final e in _prefs.entries.where((e) => e.key.contains(':$oldId:')).toList()) {
      if (e.value.value != null) {
        final newKey = e.key.replaceFirst(':$oldId:', ':$newId:');
        _prefs.putIfAbsent(newKey, () => (value: e.value.value, updatedAt: now));
      }
      _prefs[e.key] = (value: null, updatedAt: now);
    }
    onSourceRemapped?.call(oldId, newId);
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    final json = jsonEncode({
      'version': 1,
      'lists': _lists.values.map((l) => l.toJson()).toList(),
      'items': _items.values.map((i) => i.toJson()).toList(),
      'prefs': _prefs.map((k, v) => MapEntry(k, {'value': v.value, 'updatedAt': v.updatedAt})),
      'sources': _sources.values.map((s) => s.toJson()).toList(),
      'sync': syncMeta,
    });
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
  }

  // ---- Listas ----

  UserList get favorites => _lists[favoritesId]!;

  /// Listas propias (sin Favoritos), por fecha de creación.
  List<UserList> get customLists =>
      _lists.values.where((l) => !l.deleted && !l.isFavorites).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  UserList? list(String id) {
    final l = _lists[id];
    return (l == null || l.deleted) ? null : l;
  }

  UserList createList(String name) {
    final now = _now();
    final list = UserList(const Uuid().v4(), name.trim(), now, now);
    _lists[list.id] = list;
    _changed();
    return list;
  }

  void renameList(String id, String name) {
    final l = _lists[id]!;
    _lists[id] = UserList(id, name.trim(), l.createdAt, _now());
    _changed();
  }

  void deleteList(String id) {
    if (id == favoritesId) return;
    final l = _lists[id]!;
    final now = _now();
    _lists[id] = UserList(id, l.name, l.createdAt, now, deleted: true);
    for (final item in itemsOf(id)) {
      _items[item.id] = ListItem(item.listId, item.item, item.addedAt, now, deleted: true);
    }
    _changed();
  }

  // ---- Elementos ----

  /// Elementos de una lista, los más recientes primero.
  List<ListItem> itemsOf(String listId) =>
      _items.values.where((i) => i.listId == listId && !i.deleted).toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  int countOf(String listId) => _items.values.where((i) => i.listId == listId && !i.deleted).length;

  bool contains(String listId, ItemRef ref) {
    final i = _items['$listId|${ref.key}'];
    return i != null && !i.deleted;
  }

  bool isFavorite(ItemRef ref) => contains(favoritesId, ref);

  void addAll(String listId, Iterable<ItemSnapshot> snapshots) {
    final now = _now();
    for (final s in snapshots) {
      final id = '$listId|${s.ref.key}';
      final existing = _items[id];
      if (existing != null && !existing.deleted) continue;
      _items[id] = ListItem(listId, s, now, now);
    }
    _changed();
  }

  void removeAll(String listId, Iterable<ItemRef> refs) {
    final now = _now();
    for (final r in refs) {
      final existing = _items['$listId|${r.key}'];
      if (existing == null || existing.deleted) continue;
      _items[existing.id] = ListItem(listId, existing.item, existing.addedAt, now, deleted: true);
    }
    _changed();
  }

  /// Añade o quita de Favoritos. Devuelve true si queda en favoritos.
  bool toggleFavorite(ItemSnapshot s) {
    if (isFavorite(s.ref)) {
      removeAll(favoritesId, [s.ref]);
      return false;
    }
    addAll(favoritesId, [s]);
    return true;
  }

  // ---- Preferencias sincronizables ----

  String? pref(String key) => _prefs[key]?.value;

  void setPref(String key, String? value) {
    _prefs[key] = (value: value, updatedAt: _now());
    _changed();
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../komga/models.dart';
import 'app_state.dart';

/// Tags de los capítulos de una biblioteca: los que KofuSync lee del ComicInfo.xml de
/// cada archivo, más los que Komga ya tenga importados.
class ComicTagIndex {
  final List<KomgaBook> books;
  final Map<String, List<String>> tagsOf; // id del libro -> tags
  final List<String> allTags;
  final bool scanning; // KofuSync aún está leyendo archivos
  final bool kofusync; // KofuSync tiene la carpeta configurada

  ComicTagIndex._(this.books, this.tagsOf, this.allTags, this.scanning, this.kofusync);

  static final _cache = <String, (DateTime, ComicTagIndex)>{};

  /// Final de una ruta (carpeta del autor + archivo) para emparejar las de Komga y KofuSync,
  /// que montan la misma carpeta en sitios distintos.
  static String pathKey(String path) {
    final parts = path.replaceAll('\\', '/').split('/').where((p) => p.isNotEmpty).toList();
    return parts.skip(parts.length < 2 ? 0 : parts.length - 2).join('/').toLowerCase();
  }

  static Future<ComicTagIndex> load(AppState state, String sourceId, String libraryId, {bool force = false}) async {
    final key = '$sourceId|$libraryId';
    final hit = _cache[key];
    if (!force && hit != null && DateTime.now().difference(hit.$1).inMinutes < 5 && !hit.$2.scanning) {
      return hit.$2;
    }
    final booksFuture = state.client(sourceId).allBooks(libraryId);
    Map<String, List<String>> files = const {};
    var scanning = false;
    var configured = false;
    final sync = state.sync;
    if (sync.configured) {
      try {
        final base = Uri.parse(sync.url!);
        final res = await http
            .get(base.replace(path: '${base.path}/comics/tags'), headers: {'Authorization': 'Bearer ${sync.token}'})
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          configured = j['configured'] == true;
          scanning = j['scanning'] == true;
          files = {
            for (final e in (j['files'] as Map? ?? const {}).entries)
              pathKey('${e.key}'): [for (final t in e.value as List) '$t'],
          };
        }
      } catch (_) {
        // Sin KofuSync (o versión antigua): solo los tags de Komga.
      }
    }
    final books = await booksFuture;
    final tagsOf = <String, List<String>>{};
    final all = <String>{};
    for (final b in books) {
      final tags = {...b.tags.map((t) => t.toLowerCase()), ...?files[pathKey(b.url)]};
      if (tags.isEmpty) continue;
      tagsOf[b.id] = tags.toList();
      all.addAll(tags);
    }
    final index = ComicTagIndex._(books, tagsOf, all.toList()..sort(), scanning, configured);
    _cache[key] = (DateTime.now(), index);
    return index;
  }

  /// Capítulos cuyo nombre contiene [name] y que tienen TODOS los [tags].
  List<KomgaBook> search(String name, List<String> tags) {
    final q = name.trim().toLowerCase();
    return books.where((b) {
      if (q.isNotEmpty && !b.title.toLowerCase().contains(q) && !b.name.toLowerCase().contains(q)) return false;
      if (tags.isEmpty) return true;
      final own = tagsOf[b.id];
      return own != null && tags.every(own.contains);
    }).toList();
  }
}

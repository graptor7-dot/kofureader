import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/source.dart';
import '../data/user_data.dart' show ItemKind, ItemRef;
import 'models.dart';

class KomgaException implements Exception {
  final String message;
  final int? statusCode;

  KomgaException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Cliente HTTP para un único servidor Komga.
class KomgaClient {
  final Source source;
  final String secret;
  final http.Client _http;

  KomgaClient(this.source, this.secret, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 15);

  /// Cabeceras de autenticación; también las usan las imágenes.
  Map<String, String> get authHeaders => switch (source.authType) {
    AuthType.apiKey => {'X-API-Key': secret},
    AuthType.basic => {'Authorization': 'Basic ${base64Encode(utf8.encode('${source.username}:$secret'))}'},
  };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(source.baseUrl);
    return base.replace(
      path: '${base.path}/api/v1$path',
      queryParameters: query?.map((k, v) => MapEntry(k, v is List ? v.map((e) => '$e').toList() : '$v')),
    );
  }

  String seriesThumbnailUrl(String seriesId) => _uri('/series/$seriesId/thumbnail').toString();
  String bookThumbnailUrl(String bookId) => _uri('/books/$bookId/thumbnail').toString();
  String thumbnailUrl(ItemRef ref) =>
      ref.kind == ItemKind.series ? seriesThumbnailUrl(ref.komgaId) : bookThumbnailUrl(ref.komgaId);
  String pageUrl(String bookId, int page) => _uri('/books/$bookId/pages/$page').toString();

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    final http.Response res;
    try {
      res = await _http
          .get(_uri(path, query), headers: {...authHeaders, 'Accept': 'application/json'})
          .timeout(_timeout);
    } catch (e) {
      throw KomgaException('No se puede conectar con ${source.name}\n($e)');
    }
    _check(res);
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  void _check(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw KomgaException('Credenciales incorrectas en ${source.name}', res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw KomgaException('Error ${res.statusCode} en ${source.name}', res.statusCode);
    }
  }

  /// Comprueba URL y credenciales (endpoint estable en todas las versiones de Komga 1.x).
  Future<void> testConnection() => _get('/libraries');

  Future<List<KomgaLibrary>> libraries() async {
    final json = await _get('/libraries') as List;
    return json.map((e) => KomgaLibrary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<KomgaPage<KomgaSeries>> series({
    required String libraryId,
    int page = 0,
    int size = 60,
    String? search,
    SeriesSort sort = SeriesSort.title,
    Set<ReadStatus> readStatus = const {},
  }) async {
    final json = await _get('/series', {
      'library_id': libraryId,
      'page': page,
      'size': size,
      'sort': sort.api,
      if (search != null && search.isNotEmpty) 'search': search,
      if (readStatus.isNotEmpty) 'read_status': readStatus.map((s) => s.api).toList(),
    });
    return KomgaPage.fromJson(json as Map<String, dynamic>, KomgaSeries.fromJson);
  }

  /// Nº de series que cumplen los filtros (para elegir al azar sin descargarlas todas).
  Future<int> seriesCount({required String libraryId, String? search, Set<ReadStatus> readStatus = const {}}) async =>
      (await series(libraryId: libraryId, size: 1, search: search, readStatus: readStatus)).totalElements;

  /// La serie en la posición [index] con los filtros dados.
  Future<KomgaSeries?> seriesAt(
    int index, {
    required String libraryId,
    String? search,
    Set<ReadStatus> readStatus = const {},
  }) async {
    final p = await series(libraryId: libraryId, page: index, size: 1, search: search, readStatus: readStatus);
    return p.content.firstOrNull;
  }

  /// Libros empezados, los leídos más recientemente primero.
  Future<List<KomgaBook>> inProgressBooks({int size = 20}) async {
    final json = await _get('/books', {
      'read_status': 'IN_PROGRESS',
      'sort': 'readProgress.readDate,desc',
      'size': size,
    });
    return KomgaPage.fromJson(json as Map<String, dynamic>, KomgaBook.fromJson).content;
  }

  Future<KomgaSeries> seriesById(String id) async =>
      KomgaSeries.fromJson(await _get('/series/$id') as Map<String, dynamic>);

  /// Todos los libros de una serie, ordenados por número.
  Future<List<KomgaBook>> books(String seriesId) async {
    final result = <KomgaBook>[];
    var page = 0;
    while (true) {
      final json = await _get('/series/$seriesId/books', {
        'page': page,
        'size': 500,
        'sort': 'metadata.numberSort,asc',
      });
      final p = KomgaPage.fromJson(json as Map<String, dynamic>, KomgaBook.fromJson);
      result.addAll(p.content);
      if (p.last) return result;
      page++;
    }
  }

  Future<KomgaBook> book(String id) async => KomgaBook.fromJson(await _get('/books/$id') as Map<String, dynamic>);

  Future<List<KomgaPageInfo>> pages(String bookId) async {
    final json = await _get('/books/$bookId/pages') as List;
    return json.map((e) => KomgaPageInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> markProgress(String bookId, {required int page, bool completed = false}) async {
    final res = await _http
        .patch(
          _uri('/books/$bookId/read-progress'),
          headers: {...authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(completed ? {'completed': true} : {'page': page}),
        )
        .timeout(_timeout);
    _check(res);
  }

  void close() => _http.close();
}

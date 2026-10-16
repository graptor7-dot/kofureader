import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Caché de portadas en disco: se muestran al instante y no se vuelven a
/// descargar en cada arranque. Se renuevan pasados [maxAge] por si cambian en Komga.
abstract final class CoverCache {
  static const maxAge = Duration(days: 7);
  static Directory? _dir;
  static final _client = http.Client();

  static Future<void> init() async {
    final base = await getApplicationCacheDirectory();
    _dir = await Directory('${base.path}${Platform.pathSeparator}covers').create(recursive: true);
  }

  /// Nombre de fichero estable a partir de la URL.
  static File? fileFor(String url) {
    final dir = _dir;
    if (dir == null) return null;
    final name = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  static Future<Uint8List> load(String url, Map<String, String> headers) async {
    final file = fileFor(url);
    if (file != null && await file.exists()) {
      final age = DateTime.now().difference(await file.lastModified());
      final bytes = await file.readAsBytes();
      // Caducada: se muestra igualmente y se renueva por detrás.
      if (age > maxAge) unawaited(_fetch(url, headers, file).catchError((_) => Uint8List(0)));
      if (bytes.isNotEmpty) return bytes;
    }
    return _fetch(url, headers, file);
  }

  static Future<Uint8List> _fetch(String url, Map<String, String> headers, File? file) async {
    final res = await _client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('Portada no disponible (${res.statusCode})');
    final bytes = res.bodyBytes;
    if (file != null) {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    }
    return bytes;
  }

  static Future<int> sizeBytes() async {
    final dir = _dir;
    if (dir == null || !await dir.exists()) return 0;
    var total = 0;
    await for (final f in dir.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  static Future<void> clear() async {
    final dir = _dir;
    if (dir == null || !await dir.exists()) return;
    await for (final f in dir.list()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    PaintingBinding.instance.imageCache.clear();
  }
}

/// Imagen de portada que pasa por [CoverCache].
@immutable
class CachedCoverImage extends ImageProvider<CachedCoverImage> {
  final String url;
  final Map<String, String> headers;

  const CachedCoverImage(this.url, {this.headers = const {}});

  @override
  Future<CachedCoverImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedCoverImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1, debugLabel: url);
  }

  static Future<ui.Codec> _load(CachedCoverImage key, ImageDecoderCallback decode) async {
    final bytes = await CoverCache.load(key.url, key.headers);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  // Las cabeceras no forman parte de la identidad: la misma portada es la misma imagen.
  @override
  bool operator ==(Object other) => other is CachedCoverImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

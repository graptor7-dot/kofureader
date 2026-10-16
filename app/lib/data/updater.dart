import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Una versión publicada en GitHub Releases.
class AppRelease {
  final String version; // sin la "v"
  final String pageUrl;
  final String? notes;
  final Map<String, String> assets; // nombre -> URL de descarga

  AppRelease(this.version, this.pageUrl, this.notes, this.assets);
}

/// Busca versiones nuevas en GitHub Releases y las instala.
///
/// - Android: descarga el APK y abre el instalador del sistema.
/// - Windows: descarga el .zip, sustituye los ficheros y reinicia la app.
/// - iPad: solo avisa; hay que instalar el .ipa con iloader/SideStore.
class Updater extends ChangeNotifier {
  static const _repo = 'graptor7-dot/kofureader';

  String currentVersion = '';
  AppRelease? available;
  bool checking = false;
  double? progress; // no nulo mientras se descarga
  String? error;

  Future<void> init() async {
    currentVersion = (await PackageInfo.fromPlatform()).version;
  }

  bool get canInstallInApp => Platform.isAndroid || Platform.isWindows;

  String? get _assetName => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'KofuReader-android.apk',
    TargetPlatform.windows => 'KofuReader-windows.zip',
    TargetPlatform.iOS => 'KofuReader-ios.ipa',
    _ => null,
  };

  /// Compara versiones "1.2.10" > "1.2.9".
  static bool isNewer(String candidate, String current) {
    List<int> parts(String v) => v.split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(candidate), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Devuelve true si hay una versión más nueva.
  Future<bool> check() async {
    checking = true;
    error = null;
    notifyListeners();
    try {
      final res = await http
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) {
        available = null; // aún no hay versiones publicadas (o el repo es privado)
        return false;
      }
      if (res.statusCode != 200) throw Exception('GitHub respondió ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final release = AppRelease(
        (j['tag_name'] as String).replaceFirst(RegExp('^v'), ''),
        j['html_url'] as String,
        j['body'] as String?,
        {
          for (final a in (j['assets'] as List).cast<Map<String, dynamic>>())
            a['name'] as String: a['browser_download_url'] as String,
        },
      );
      available = isNewer(release.version, currentVersion) ? release : null;
      return available != null;
    } catch (e) {
      error = 'No se pudo comprobar: $e';
      return false;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> openReleasePage() async {
    final url = available?.pageUrl ?? 'https://github.com/$_repo/releases';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Descarga e instala la versión disponible.
  Future<void> install() async {
    final release = available;
    final name = _assetName;
    final url = name == null ? null : release?.assets[name];
    if (release == null || url == null || !canInstallInApp) {
      await openReleasePage();
      return;
    }
    error = null;
    progress = 0;
    notifyListeners();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await _download(url, file);
      if (Platform.isAndroid) {
        final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
        if (r.type != ResultType.done) throw Exception(r.message);
      } else if (Platform.isWindows) {
        await _installWindows(file, dir);
      }
    } catch (e) {
      error = 'No se pudo actualizar: $e';
    } finally {
      progress = null;
      notifyListeners();
    }
  }

  Future<void> _download(String url, File file) async {
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw Exception('Descarga fallida (${res.statusCode})');
      final total = res.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// Descomprime la versión nueva y lanza un script que, cuando la app se cierra,
  /// copia los ficheros encima de la instalación actual y la vuelve a abrir.
  Future<void> _installWindows(File zip, Directory temp) async {
    final staging = Directory('${temp.path}\\kofureader_update');
    if (await staging.exists()) await staging.delete(recursive: true);
    await extractFileToDisk(zip.path, staging.path);
    final exe = Platform.resolvedExecutable;
    final installDir = File(exe).parent.path;
    final script = File('${temp.path}\\kofureader_update.cmd');
    await script.writeAsString(
      '@echo off\r\n'
      'timeout /t 2 /nobreak >nul\r\n'
      'robocopy "${staging.path}" "$installDir" /E /IS /IT /NFL /NDL /NJH /NJS /NP >nul\r\n'
      'start "" "$exe"\r\n',
    );
    await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached);
    exit(0);
  }
}

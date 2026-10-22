import 'dart:async';

import 'package:flutter/foundation.dart';

import '../komga/models.dart';
import 'app_state.dart';
import 'remote_link.dart';
import 'source.dart';

/// Una pantalla (dispositivo con el lector abierto, o la tele) vista desde el mando.
class RemoteScreenInfo {
  final String deviceId;
  final String name;
  final String kind; // app o tv
  final String title;
  final String series;
  final String bookId;
  final int page;
  final int total;
  final String mode;
  final bool hasNext;
  final bool hasPrev;
  final bool atEnd;

  RemoteScreenInfo(Map<String, dynamic> j)
    : deviceId = '${j['deviceId']}',
      name = '${j['name'] ?? 'Pantalla'}',
      kind = '${j['kind'] ?? 'app'}',
      title = '${j['title'] ?? ''}',
      series = '${j['series'] ?? ''}',
      bookId = '${j['bookId'] ?? ''}',
      page = (j['page'] as num?)?.toInt() ?? 0,
      total = (j['total'] as num?)?.toInt() ?? 0,
      mode = '${j['mode'] ?? 'pagedRtl'}',
      hasNext = j['hasNext'] == true,
      hasPrev = j['hasPrev'] == true,
      atEnd = j['atEnd'] == true;

  bool get isTv => kind == 'tv';
  bool get vertical => mode == 'vertical';
  bool get rtl => mode == 'pagedRtl';
  bool get hasBook => title.isNotEmpty || bookId.isNotEmpty;
}

/// Lo que se está leyendo en la tele (lo gestiona el móvil: la tele no habla con Komga).
class TvSession {
  final String tvId;
  final Source source;
  final List<KomgaBook> books;
  int index;

  TvSession(this.tvId, this.source, this.books, this.index);

  KomgaBook get book => books[index];
  bool get hasNext => index < books.length - 1;
  bool get hasPrev => index > 0;
}

/// Conexión del móvil como mando, compartida por toda la app.
///
/// La usa la pantalla de modo mando y la función "enviar a la tele".
/// También guarda en Komga el progreso de lo que se lee en la tele.
class RemoteHub extends ChangeNotifier {
  final AppState state;
  RemoteLink? _link;
  int _users = 0;
  List<RemoteScreenInfo> screens = [];
  bool received = false;

  /// Tele a la que se enviará el próximo libro que se abra (modo "elegir qué leer").
  String? castTarget;
  TvSession? tvSession;

  Completer<String?>? _pairing;
  Timer? _progressTimer;
  int _lastSavedPage = -1;

  RemoteHub(this.state);

  bool get available => state.sync.configured;
  bool get connected => _link?.connected ?? false;
  String? get error => _link?.connected == true ? null : _link?.error;

  /// Pantallas de otros dispositivos (sin este).
  List<RemoteScreenInfo> get others => screens.where((s) => s.deviceId != deviceId(state)).toList();

  RemoteScreenInfo? screen(String id) => screens.where((s) => s.deviceId == id).firstOrNull;

  /// Engancha la conexión mientras alguien la use (pantalla de mando, envío a la tele).
  void acquire() {
    _users++;
    _link ??= RemoteLink.create(state, RemoteRole.remote, onMessage: _onMessage)?..addListener(notifyListeners);
  }

  void release() {
    _users = (_users - 1).clamp(0, 1 << 20);
    if (_users == 0 && castTarget == null && tvSession == null) {
      _link?.close();
      _link = null;
      received = false;
      screens = [];
    }
  }

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'screens':
        screens = [for (final s in (msg['screens'] as List).cast<Map>()) RemoteScreenInfo(s.cast<String, dynamic>())];
        received = true;
        _trackTvProgress();
        // Si la tele se ha desconectado, se olvida lo que se leía en ella.
        final session = tvSession;
        if (session != null && screen(session.tvId) == null) tvSession = null;
        notifyListeners();
      case 'paired':
        _pairing?.complete(msg['ok'] == true ? '${msg['deviceId']}' : null);
        _pairing = null;
    }
  }

  void command(String to, String cmd, [Map<String, dynamic> args = const {}]) => _link?.command(to, cmd, args);
  void attach(String to) => _link?.attach(to);

  /// Empareja una tele con el código que muestra. Devuelve su id o null si el código no vale.
  Future<String?> pairTv(String code) async {
    acquire();
    try {
      final completer = _pairing = Completer<String?>();
      _link?.sendRaw({'type': 'pair', 'code': code.trim()});
      return await completer.future.timeout(const Duration(seconds: 8), onTimeout: () => null);
    } finally {
      release();
    }
  }

  // ---- Enviar a la tele ----

  void startChoosing(String tvId) {
    acquire();
    castTarget = tvId;
    notifyListeners();
  }

  void cancelChoosing() {
    if (castTarget == null) return;
    castTarget = null;
    notifyListeners();
    release();
  }

  /// Abre [books][index] en la tele elegida. El móvil le pasa al servidor cómo llegar
  /// a Komga (solo se guarda en memoria) y la tele pide las páginas al servidor.
  Future<void> castBook(String tvId, Source source, List<KomgaBook> books, int index) async {
    final client = state.client(source.id);
    final book = books[index];
    final results = await Future.wait([
      client.pages(book.id),
      state.effectiveMode(source.id, book.libraryId, book.seriesId),
      client.book(book.id).then<KomgaBook?>((b) => b, onError: (_) => null),
    ]);
    final pages = results[0] as List<KomgaPageInfo>;
    final mode = results[1] as ReadingMode;
    final fresh = (results[2] as KomgaBook?) ?? book;
    final start = fresh.inProgress ? fresh.readProgress!.page.clamp(1, pages.isEmpty ? 1 : pages.length) : 1;
    command(tvId, 'open', {
      'baseUrl': source.baseUrl,
      'headers': client.authHeaders,
      'bookId': book.id,
      'title': book.title,
      'series': book.seriesTitle,
      'mode': mode.name,
      'spreads': state.data.pref('doublepage') != '0',
      'startPage': start,
      'pages': [
        for (final p in pages) {'n': p.number, 'w': p.width, 'h': p.height},
      ],
    });
    // La sesión de la tele mantiene viva la conexión. Si se venía de "elegir qué leer",
    // se reutiliza esa referencia en vez de pedir otra.
    final wasChoosing = castTarget == tvId;
    castTarget = null;
    if (tvSession == null && !wasChoosing) acquire();
    if (tvSession != null && wasChoosing) release();
    tvSession = TvSession(tvId, source, books, index);
    _lastSavedPage = start;
    notifyListeners();
  }

  Future<void> tvNextChapter() async {
    final s = tvSession;
    if (s == null || !s.hasNext) return;
    await castBook(s.tvId, s.source, s.books, s.index + 1);
  }

  Future<void> tvPrevChapter() async {
    final s = tvSession;
    if (s == null || !s.hasPrev) return;
    await castBook(s.tvId, s.source, s.books, s.index - 1);
  }

  /// Cierra el libro en la tele (vuelve a la pantalla de espera).
  void tvClose() {
    final s = tvSession;
    if (s == null) return;
    command(s.tvId, 'exit');
    tvSession = null;
    notifyListeners();
    release();
  }

  /// La tele publica su página; el móvil la guarda en Komga (con un poco de retraso).
  void _trackTvProgress() {
    final s = tvSession;
    if (s == null) return;
    final info = screen(s.tvId);
    if (info == null || info.bookId != s.book.id || info.page <= 0 || info.page == _lastSavedPage) return;
    _progressTimer?.cancel();
    final page = info.page;
    final completed = info.atEnd || (info.total > 0 && page >= info.total);
    _progressTimer = Timer(const Duration(milliseconds: 1500), () {
      _lastSavedPage = page;
      state.client(s.source.id).markProgress(s.book.id, page: page, completed: completed).catchError((_) {});
    });
  }
}

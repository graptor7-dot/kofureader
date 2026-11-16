import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/app_scope.dart';
import '../../data/app_state.dart';
import '../../data/downloads.dart';
import '../../data/snapshots.dart';
import '../../data/source.dart';
import '../../komga/komga_client.dart';
import '../../komga/models.dart';
import '../../theme.dart';
import '../widgets/cover_card.dart';
import '../../data/remote_link.dart';
import '../desktop.dart';
import '../extras_screens.dart' show showTagsSheet, showRatingDialog, addToTop10;
import '../series_screen.dart' show SeriesScreen;
import '../widgets/selection.dart' show showToast;
import '../widgets/list_sheets.dart';

/// Lector de un libro, con paso al siguiente/anterior de la misma lista.
class ReaderScreen extends StatefulWidget {
  final Source source;
  final List<KomgaBook> books;
  final int initialIndex;

  /// Página en la que abrir el primer libro (p. ej. desde un marcador); si no, la del progreso.
  final int? startPage;

  const ReaderScreen({
    super.key,
    required this.source,
    required this.books,
    required this.initialIndex,
    this.startPage,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final KomgaClient _client = AppScope.read(context).client(widget.source.id);
  late int _index = widget.initialIndex;
  List<KomgaPageInfo>? _pages;
  ReadingMode _mode = ReadingMode.pagedRtl;
  int _page = 1; // página actual, empieza en 1
  int _startPage = 1;
  int _loadId = 0; // cambia al abrir otro libro, recrea las vistas
  String? _error;
  bool _overlay = false;
  Timer? _saveTimer;
  int? _pendingSave;

  /// Modo mando: este lector se anuncia como pantalla y obedece al móvil.
  RemoteLink? _remote;

  // Claves para llamar a las vistas desde el mando; cambian cuando se recrea la vista.
  GlobalKey<_PagedReaderState> _pagedKey = GlobalKey();
  GlobalKey<_VerticalReaderState> _verticalKey = GlobalKey();
  String? _viewSignature;

  KomgaBook get _book => widget.books[_index];

  void _refreshKeys(String signature) {
    if (signature == _viewSignature) return;
    _viewSignature = signature;
    _pagedKey = GlobalKey();
    _verticalKey = GlobalKey();
  }

  /// Publica en el mando qué se está leyendo.
  void _publishState() {
    final pages = _pages;
    _remote?.publishState({
      'title': _book.title,
      'series': _book.seriesTitle,
      'page': _page,
      'total': pages?.length ?? 0,
      'mode': _mode.name,
      'hasNext': _hasNext,
      'hasPrev': _hasPrev,
    });
  }

  /// Órdenes que llegan del móvil.
  void _onRemote(Map<String, dynamic> msg) {
    if (!mounted) return;
    if (msg['type'] == 'attach') {
      showToast(context, 'Mando conectado: ${msg['fromName'] ?? 'móvil'}', icon: Icons.settings_remote_rounded);
      _publishState();
      return;
    }
    if (msg['type'] != 'command') return;
    final paged = _pagedKey.currentState;
    final vertical = _verticalKey.currentState;
    switch (msg['cmd']) {
      case 'next':
        paged != null ? paged._next() : vertical?.scrollByFraction(0.85, animate: true);
      case 'prev':
        paged != null ? paged._prev() : vertical?.scrollByFraction(-0.85, animate: true);
      case 'scroll':
        vertical?.scrollByFraction((msg['dy'] as num).toDouble());
      case 'fling':
        vertical?.fling((msg['v'] as num).toDouble());
      case 'nextChapter':
        _nextBook();
      case 'prevChapter':
        _prevBook();
      case 'overlay':
        setState(() => _overlay = !_overlay);
      case 'exit':
        Navigator.maybePop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Que la pantalla no se apague mientras se lee.
    WakelockPlus.enable().catchError((_) {});
    _remote = RemoteLink.create(AppScope.read(context), RemoteRole.screen, onMessage: _onRemote);
    _openBook(_index);
  }

  @override
  void dispose() {
    _flushProgress();
    _remote?.close();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _openBook(int index) async {
    _flushProgress();
    setState(() {
      _index = index;
      _pages = null;
      _error = null;
    });
    final state = AppScope.read(context);
    final sourceId = widget.source.id;
    try {
      final book = widget.books[index];
      final local = state.downloads.downloaded(sourceId, book.id);
      final modeFuture = state.effectiveMode(sourceId, book.libraryId, book.seriesId);
      // El progreso de la lista puede estar desfasado: se pide el libro de nuevo
      // (si está descargado y no hay conexión, se sigue sin él).
      final freshFuture = local == null
          ? _client.book(book.id)
          : _client.book(book.id).timeout(const Duration(seconds: 4)).then<KomgaBook?>((b) => b, onError: (_) => null);
      final pages = local?.pages ?? await _client.pages(book.id);
      final fresh = await freshFuture;
      final mode = await modeFuture;
      if (!mounted || index != _index) return;
      final pending = state.downloads.pendingProgress(sourceId, book.id);
      final known = fresh ?? book;
      final int start;
      if (widget.startPage != null && index == widget.initialIndex && !_usedStartPage) {
        _usedStartPage = true;
        start = widget.startPage!;
      } else if (pending != null) {
        start = pending.completed ? 1 : pending.page;
      } else {
        start = known.inProgress ? known.readProgress!.page : 1;
      }
      setState(() {
        _local = local;
        _mode = mode;
        _pages = pages;
        _page = start.clamp(1, pages.isEmpty ? 1 : pages.length);
        _startPage = _page;
        _loadId++;
      });
      _precache(_page, behind: 1);
      _publishState();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  bool _usedStartPage = false;

  /// Libro abierto desde disco (null = se lee de Komga).
  DownloadedBook? _local;

  /// Página a tamaño original (de disco o de Komga).
  ImageProvider _source(int page, [_Segment? segment]) {
    final local = segment == null ? _local : segment.local;
    if (local != null) return FileImage(AppScope.read(context).downloads.pageFile(local, page));
    final book = segment == null ? _book : widget.books[segment.index];
    return NetworkImage(_client.pageUrl(book.id, page), headers: _client.authHeaders);
  }

  /// Página descodificada al tamaño de la pantalla (x1.5 para tener margen al hacer zoom).
  /// Descodificar a tamaño completo ocupa ~20 MB por página y llena la caché enseguida.
  ImageProvider _image(int page, [_Segment? segment]) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_mode == ReadingMode.vertical) {
      final width = (size.width.clamp(0, 800) * dpr * 1.25).round();
      return ResizeImage(_source(page, segment), width: width, allowUpscaling: false);
    }
    return ResizeImage(
      _source(page),
      width: (size.width * dpr * 1.5).round(),
      height: (size.height * dpr * 1.5).round(),
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  // ---- Progreso ----

  void _onPageChanged(int page, {bool force = false}) {
    if (page == _page && !force) return;
    setState(() => _page = page);
    _pendingSave = page;
    _saveTimer?.cancel();
    final isLast = page == _pages!.length;
    _saveTimer = Timer(Duration(milliseconds: isLast ? 0 : 1200), _flushProgress);
    _precache(page);
    _publishState();
  }

  void _flushProgress() {
    _saveTimer?.cancel();
    final page = _pendingSave;
    final pages = _pages;
    if (page == null || pages == null) return;
    _pendingSave = null;
    final downloads = AppScope.read(context).downloads;
    final sourceId = widget.source.id;
    final bookId = _book.id;
    final completed = page >= pages.length;
    // Se apunta antes de enviar: si no hay conexión, queda para más tarde.
    downloads.queueProgress(sourceId, bookId, page, completed);
    _client
        .markProgress(bookId, page: page, completed: completed)
        .then((_) => downloads.clearPendingProgress(sourceId, bookId, page), onError: (_) {});
  }

  /// Precarga las siguientes páginas (y [behind] anteriores, por si se vuelve atrás).
  void _precache(int page, {int behind = 1}) {
    final pages = _pages;
    if (pages == null || !mounted) return;
    const ahead = 5;
    for (var p = page; p <= page + ahead && p <= pages.length; p++) {
      precacheImage(_image(pages[p - 1].number), context, onError: (_, _) {});
    }
    for (var p = page - 1; p >= page - behind && p >= 1; p--) {
      precacheImage(_image(pages[p - 1].number), context, onError: (_, _) {});
    }
  }

  // ---- Lectura vertical continua ----
  //
  // En vertical, al acercarse al final se encadena el siguiente libro debajo,
  // sin salir del scroll. Al cruzar al siguiente, el anterior queda leído.

  List<_Segment> _segments = const [];
  int _segmentsLoadId = -1;
  bool _appending = false;
  final _appendFailed = <int>{};

  Future<void> _appendNext() async {
    if (_appending || _segments.isEmpty) return;
    final next = _segments.last.index + 1;
    if (next >= widget.books.length || _appendFailed.contains(next)) return;
    _appending = true;
    try {
      final state = AppScope.read(context);
      final book = widget.books[next];
      final mode = await state.effectiveMode(widget.source.id, book.libraryId, book.seriesId);
      if (mode != ReadingMode.vertical) {
        _appendFailed.add(next);
        if (mounted) setState(() {});
        return;
      }
      final local = state.downloads.downloaded(widget.source.id, book.id);
      final pages = local?.pages ?? await _client.pages(book.id);
      if (!mounted || _mode != ReadingMode.vertical || _segments.last.index != next - 1) return;
      if (pages.isEmpty) {
        setState(() => _appendFailed.add(next));
        return;
      }
      setState(() => _segments = [..._segments, _Segment(next, pages, local)]);
    } catch (_) {
      _appendFailed.add(next); // sin conexión: se verá la página de fin de capítulo
      if (mounted) setState(() {});
    } finally {
      _appending = false;
    }
  }

  void _onVerticalPage(int segment, int page) {
    final s = _segments[segment];
    if (s.index != _index) {
      // Se ha pasado al libro siguiente (o se ha vuelto al anterior).
      if (s.index > _index && _pages != null) _pendingSave = _pages!.length;
      _flushProgress();
      setState(() {
        _index = s.index;
        _pages = s.pages;
        _local = s.local;
        _page = 0;
      });
    }
    _onPageChanged(page);
  }

  // ---- Navegación entre libros ----

  bool get _hasNext => _index < widget.books.length - 1;
  bool get _hasPrev => _index > 0;

  void _nextBook() {
    if (_hasNext) {
      _openBook(_index + 1);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Es el último libro')));
    }
  }

  void _prevBook() {
    if (_hasPrev) _openBook(_index - 1);
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            TextButton(onPressed: () => _openBook(_index), child: const Text('Reintentar')),
          ],
        ),
      );
    } else if (_pages == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_pages!.isEmpty) {
      body = const Center(
        child: Text('Libro sin páginas', style: TextStyle(color: Colors.white)),
      );
    } else if (_mode == ReadingMode.vertical) {
      _refreshKeys('v$_loadId');
      if (_segmentsLoadId != _loadId) {
        _segmentsLoadId = _loadId;
        _segments = [_Segment(_index, _pages!, _local)];
        _appendFailed.clear();
      }
      final last = _segments.last.index;
      final more = last + 1 < widget.books.length && !_appendFailed.contains(last + 1);
      body = _VerticalReader(
        key: _verticalKey,
        image: _image,
        segments: _segments,
        titles: [for (final s in _segments) widget.books[s.index].title],
        startPage: _startPage,
        onPageChanged: _onVerticalPage,
        onNearEnd: _appendNext,
        onTap: () => setState(() => _overlay = !_overlay),
        endPage: more
            ? const Center(child: CircularProgressIndicator(color: Colors.white54))
            : _ChapterEndPage(
                finished: widget.books[last],
                next: last + 1 < widget.books.length ? widget.books[last + 1] : null,
                onNext: () => _openBook(last + 1),
                onExit: () => Navigator.maybePop(context),
              ),
      );
    } else {
      final spreads = _useSpreads;
      _refreshKeys('p$_loadId${_mode.name}$spreads');
      body = _PagedReader(
        key: _pagedKey,
        image: _image,
        pages: _pages!,
        startPage: _page,
        rtl: _mode == ReadingMode.pagedRtl,
        spreads: spreads,
        onPageChanged: _onPageChanged,
        onCenterTap: () => setState(() => _overlay = !_overlay),
        onPastEnd: _nextBook,
        onBeforeStart: _prevBook,
        endPage: _chapterEnd(),
      );
    }

    // Filtro nocturno (de este dispositivo): tono cálido y oscurecer.
    final data = AppScope.of(context).data;
    final warm = double.tryParse(data.localPref('night_warm') ?? '') ?? 0;
    final dim = double.tryParse(data.localPref('night_dim') ?? '') ?? 0;
    if (warm > 0) {
      body = ColorFiltered(
        colorFilter: ColorFilter.mode(Color.lerp(Colors.white, const Color(0xFFFFA64D), warm)!, BlendMode.multiply),
        child: body,
      );
    }

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _onEscape},
      child: Focus(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(child: body),
              if (dim > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
                  ),
                ),
              if (_overlay) ..._buildOverlay(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Esc: primero sale de la pantalla completa; si no lo está, cierra el lector.
  Future<void> _onEscape() async {
    if (await isFullScreen()) {
      await setFullScreen(false);
    } else if (mounted) {
      Navigator.maybePop(context);
    }
  }

  Future<void> _showNightFilter() async {
    final data = AppScope.read(context).data;
    await showModalBottomSheet(
      context: context,
      barrierColor: Colors.transparent, // para ver el efecto mientras se ajusta
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          double value(String key) => double.tryParse(data.localPref(key) ?? '') ?? 0;
          Widget slider(String key, String label, IconData icon, double max) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, color: Kofu.muted),
                const SizedBox(width: 12),
                SizedBox(width: 90, child: Text(label)),
                Expanded(
                  child: Slider(
                    value: value(key).clamp(0, max),
                    max: max,
                    onChanged: (v) {
                      data.setLocalPref(key, v <= 0.01 ? null : v.toStringAsFixed(2));
                      setSheet(() {});
                    },
                  ),
                ),
              ],
            ),
          );
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Filtro nocturno', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Solo en este dispositivo', style: TextStyle(color: Kofu.muted)),
                ),
                slider('night_warm', 'Tono cálido', Icons.wb_twilight_rounded, 1),
                slider('night_dim', 'Oscurecer', Icons.brightness_4_rounded, 0.8),
                TextButton(
                  onPressed: () {
                    data.setLocalPref('night_warm', null);
                    data.setLocalPref('night_dim', null);
                    setSheet(() {});
                  },
                  child: const Text('Quitar filtro'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  bool get _isLandscape {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  /// Preferencia (sincronizada) de doble página; activada salvo que se desactive.
  bool get _spreadsEnabled => AppScope.read(context).data.pref('doublepage') != '0';

  /// Doble página: en horizontal, en modo páginas y si está activada.
  bool get _useSpreads => _mode != ReadingMode.vertical && _isLandscape && _spreadsEnabled;

  Widget _chapterEnd() => _ChapterEndPage(
    finished: _book,
    next: _hasNext ? widget.books[_index + 1] : null,
    onNext: _nextBook,
    onExit: () => Navigator.maybePop(context),
  );

  List<Widget> _buildOverlay(BuildContext context) {
    final pages = _pages;
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.black.withValues(alpha: 0.8),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const BackButton(color: Colors.white),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => SeriesScreen.showFromReader(context, widget.source, _book.seriesId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _book.seriesTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Kofu.accent, fontSize: 12),
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: Kofu.accent, size: 16),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Builder(
                  builder: (context) {
                    final data = AppScope.of(context).data;
                    final snap = _book.snapshot(widget.source.id);
                    final fav = data.isFavorite(snap.ref);
                    return IconButton(
                      tooltip: fav ? 'Quitar de Favoritos' : 'Añadir a Favoritos',
                      onPressed: () => data.toggleFavorite(snap),
                      icon: Icon(
                        fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: fav ? Kofu.accent : Colors.white,
                      ),
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    final extras = AppScope.of(context).extras;
                    final snap = _book.snapshot(widget.source.id);
                    final marked = extras.isBookmarked(snap.ref, _page);
                    return IconButton(
                      tooltip: marked ? 'Quitar marcador' : 'Guardar esta página',
                      onPressed: () {
                        extras.setBookmark(snap, _page, !marked);
                        showToast(
                          context,
                          marked ? 'Marcador quitado' : 'Página $_page guardada en Marcadores',
                          icon: Icons.bookmark_rounded,
                        );
                      },
                      icon: Icon(
                        marked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        color: marked ? Kofu.accent : Colors.white,
                      ),
                    );
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: 'Más',
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onSelected: (v) {
                    final snap = _book.snapshot(widget.source.id);
                    if (v == 'list') showAddToListSheet(context, [snap]);
                    if (v == 'complete') {
                      final data = AppScope.read(context).data;
                      final now = !data.isComplete(snap.ref);
                      data.setComplete([snap], now);
                      showToast(
                        context,
                        now ? 'Marcado como edición completa' : 'Quitado de Ediciones completas',
                        icon: Icons.workspace_premium_rounded,
                      );
                    }
                    if (v == 'tags') showTagsSheet(context, [snap]);
                    if (v == 'rate') showRatingDialog(context, snap);
                    if (v == 'top') addToTop10(context, snap);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'list', child: Text('Añadir a lista')),
                    PopupMenuItem(value: 'complete', child: Text('Edición completa (sí/no)')),
                    PopupMenuItem(value: 'tags', child: Text('Etiquetas del capítulo')),
                    PopupMenuItem(value: 'rate', child: Text('Valorar capítulo')),
                    PopupMenuItem(value: 'top', child: Text('Añadir al Top 10')),
                  ],
                ),
                IconButton(
                  tooltip: 'Filtro nocturno',
                  onPressed: _showNightFilter,
                  icon: const Icon(Icons.nightlight_round, color: Colors.white),
                ),
                if (isDesktop)
                  IconButton(
                    tooltip: 'Pantalla completa (F11)',
                    onPressed: toggleFullScreen,
                    icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                  ),
                if (_mode != ReadingMode.vertical && _isLandscape)
                  IconButton(
                    tooltip: _spreadsEnabled ? 'Ver de una en una' : 'Ver a doble página',
                    onPressed: () {
                      AppScope.read(context).data.setPref('doublepage', _spreadsEnabled ? '0' : null);
                      setState(() {
                        _startPage = _page;
                        _loadId++;
                      });
                    },
                    icon: Icon(
                      _spreadsEnabled ? Icons.auto_stories_rounded : Icons.crop_portrait_rounded,
                      color: Colors.white,
                    ),
                  ),
                PopupMenuButton<ReadingMode>(
                  tooltip: 'Modo de lectura (solo ahora)',
                  icon: const Icon(Icons.chrome_reader_mode_outlined, color: Colors.white),
                  initialValue: _mode,
                  onSelected: (m) => setState(() {
                    _startPage = _page;
                    _mode = m;
                    _loadId++;
                  }),
                  itemBuilder: (_) => [
                    for (final m in ReadingMode.values) PopupMenuItem(value: m, child: Text(m.label)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      if (pages != null && pages.isNotEmpty)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.black.withValues(alpha: 0.8),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Libro anterior',
                      onPressed: _hasPrev ? _prevBook : null,
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                    ),
                    Text('$_page / ${pages.length}', style: const TextStyle(color: Colors.white)),
                    Expanded(
                      child: Directionality(
                        textDirection: _mode == ReadingMode.pagedRtl ? TextDirection.rtl : TextDirection.ltr,
                        child: Slider(
                          min: 1,
                          max: pages.length.toDouble(),
                          divisions: pages.length > 1 ? pages.length - 1 : null,
                          value: _page.toDouble(),
                          onChanged: (v) => setState(() => _page = v.round()),
                          onChangeEnd: (v) {
                            setState(() {
                              _startPage = v.round();
                              _loadId++;
                            });
                            _onPageChanged(v.round(), force: true);
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Libro siguiente',
                      onPressed: _hasNext ? _nextBook : null,
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Fin de capítulo
// ---------------------------------------------------------------------------

/// Página negra entre capítulos: indica cuál ha terminado y cuál viene.
/// Pasar página otra vez abre el siguiente; así se puede salir sin empezarlo.
class _ChapterEndPage extends StatelessWidget {
  final KomgaBook finished;
  final KomgaBook? next;
  final VoidCallback onNext;
  final VoidCallback onExit;

  const _ChapterEndPage({required this.finished, required this.next, required this.onNext, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final next = this.next;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (r) => Kofu.accentGradient.createShader(r),
                  child: const Icon(Icons.check_circle_rounded, size: 64, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Capítulo terminado',
                  style: TextStyle(color: Kofu.muted, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  finished.title,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2),
                ),
                const SizedBox(height: 32),
                Container(height: 1, width: 80, color: Kofu.outline),
                const SizedBox(height: 32),
                if (next != null) ...[
                  const Text('Siguiente', style: TextStyle(color: Kofu.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(
                    next.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text('Pasa página para empezarlo', style: TextStyle(color: Kofu.muted, fontSize: 12)),
                ] else
                  const Text(
                    'Era el último de la serie',
                    style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onExit,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Kofu.outline),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Salir'),
                    ),
                    if (next != null)
                      FilledButton.icon(
                        onPressed: onNext,
                        icon: const Icon(Icons.skip_next_rounded),
                        label: const Text('Siguiente'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo páginas
// ---------------------------------------------------------------------------

class _PagedReader extends StatefulWidget {
  final ImageProvider Function(int page) image;
  final List<KomgaPageInfo> pages;
  final int startPage;
  final bool rtl;
  final bool spreads; // doble página (iPad/PC en horizontal)
  final ValueChanged<int> onPageChanged;
  final VoidCallback onCenterTap;
  final VoidCallback onPastEnd;
  final VoidCallback onBeforeStart;
  final Widget endPage; // página de fin de capítulo, tras la última

  const _PagedReader({
    super.key,
    required this.image,
    required this.pages,
    required this.startPage,
    required this.rtl,
    required this.spreads,
    required this.onPageChanged,
    required this.onCenterTap,
    required this.onPastEnd,
    required this.onBeforeStart,
    required this.endPage,
  });

  @override
  State<_PagedReader> createState() => _PagedReaderState();
}

/// Agrupa las páginas en "vistas": una página, o dos en modo doble página.
/// La portada va sola, las páginas anchas (dobles ya unidas) también.
List<List<int>> buildSpreads(List<KomgaPageInfo> pages, {required bool spreads}) {
  if (!spreads) {
    return [
      for (var i = 0; i < pages.length; i++) [i],
    ];
  }
  bool wide(int i) => (pages[i].aspectRatio ?? 0.7) > 1;
  final views = <List<int>>[];
  var i = 0;
  while (i < pages.length) {
    if (i == 0 || wide(i) || i + 1 >= pages.length || wide(i + 1)) {
      views.add([i]);
      i++;
    } else {
      views.add([i, i + 1]);
      i += 2;
    }
  }
  return views;
}

class _PagedReaderState extends State<_PagedReader> {
  late final List<List<int>> _views = buildSpreads(widget.pages, spreads: widget.spreads);
  late final _controller = PageController(initialPage: _viewOf(widget.startPage - 1));
  final _focus = FocusNode();
  bool _zoomed = false;

  int _viewOf(int pageIndex) {
    final v = _views.indexWhere((view) => view.contains(pageIndex));
    return v < 0 ? 0 : v;
  }

  int get _current => (_controller.hasClients ? _controller.page?.round() : null) ?? _viewOf(widget.startPage - 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _next() {
    // Índice _views.length = página de fin de capítulo; pasar de ella abre el siguiente.
    if (_current >= _views.length) {
      widget.onPastEnd();
    } else {
      _controller.jumpToPage(_current + 1);
    }
  }

  void _prev() {
    if (_current <= 0) {
      widget.onBeforeStart();
    } else {
      _controller.jumpToPage(_current - 1);
    }
  }

  // En RTL la izquierda avanza.
  void _left() => widget.rtl ? _next() : _prev();
  void _right() => widget.rtl ? _prev() : _next();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _left();
      case LogicalKeyboardKey.arrowRight:
        _right();
      case LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.pageDown || LogicalKeyboardKey.space:
        _next();
      case LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.pageUp:
        _prev();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _page(int index, Alignment alignment) => KomgaImage.provider(
    widget.image(widget.pages[index].number),
    fit: BoxFit.contain,
    alignment: alignment,
    fade: false,
  );

  Widget _view(List<int> view) {
    if (view.length == 1) return SizedBox.expand(child: _page(view.first, Alignment.center));
    // En manga (RTL) la primera página del par va a la derecha.
    final first = _page(view[0], widget.rtl ? Alignment.centerLeft : Alignment.centerRight);
    final second = _page(view[1], widget.rtl ? Alignment.centerRight : Alignment.centerLeft);
    return Row(
      children: [
        Expanded(child: widget.rtl ? second : first),
        Expanded(child: widget.rtl ? first : second),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        // Rueda del ratón en escritorio.
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && !_zoomed) {
            e.scrollDelta.dy > 0 ? _next() : _prev();
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final x = d.localPosition.dx / constraints.maxWidth;
              if (x < 0.3) {
                _left();
              } else if (x > 0.7) {
                _right();
              } else {
                widget.onCenterTap();
              }
            },
            child: PageView.builder(
              controller: _controller,
              reverse: widget.rtl,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: _views.length + 1,
              // Se informa la última página visible de la vista.
              onPageChanged: (v) => widget.onPageChanged(v < _views.length ? _views[v].last + 1 : widget.pages.length),
              itemBuilder: (context, v) => v == _views.length
                  ? widget.endPage
                  : _ZoomablePage(onZoomChanged: (z) => setState(() => _zoomed = z), child: _view(_views[v])),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePage({required this.child, required this.onZoomChanged});

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final _transform = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _update() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Doble toque: quitar el zoom.
      onDoubleTap: () {
        _transform.value = Matrix4.identity();
        _update();
      },
      child: InteractiveViewer(
        transformationController: _transform,
        panEnabled: _zoomed,
        maxScale: 5,
        onInteractionEnd: (_) => _update(),
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo vertical (webtoon)
// ---------------------------------------------------------------------------

/// Un libro dentro del scroll vertical continuo.
class _Segment {
  final int index; // posición en widget.books
  final List<KomgaPageInfo> pages;
  final DownloadedBook? local;

  _Segment(this.index, this.pages, this.local);
}

class _VerticalReader extends StatefulWidget {
  final ImageProvider Function(int page, [_Segment? segment]) image;
  final List<_Segment> segments;
  final List<String> titles; // título de cada segmento (para el separador)
  final int startPage; // del primer segmento
  final void Function(int segment, int page) onPageChanged;
  final VoidCallback onNearEnd;
  final VoidCallback onTap;
  final Widget endPage; // al final del último segmento

  const _VerticalReader({
    super.key,
    required this.image,
    required this.segments,
    required this.titles,
    required this.startPage,
    required this.onPageChanged,
    required this.onNearEnd,
    required this.onTap,
    required this.endPage,
  });

  @override
  State<_VerticalReader> createState() => _VerticalReaderState();
}

class _VerticalReaderState extends State<_VerticalReader> {
  static const _maxWidth = 800.0;
  static const _fallbackRatio = 0.7;
  static const _dividerHeight = 160.0;
  ScrollController? _scroll;
  double _width = 0;
  int _laidOut = 0; // segmentos ya medidos

  // Elementos de la lista, en orden: páginas de cada segmento y un separador entre ellos.
  final List<(int segment, int page)> _items = []; // page = 0 -> separador
  final List<double> _offsets = []; // inicio de cada elemento
  double _end = 0;

  double _ratio(KomgaPageInfo p) => p.aspectRatio ?? _fallbackRatio;

  void _layout(double width) {
    if (width != _width) {
      _width = width;
      _laidOut = 0;
      _items.clear();
      _offsets.clear();
      _end = 0;
    }
    for (var s = _laidOut; s < widget.segments.length; s++) {
      if (s > 0) {
        _items.add((s, 0));
        _offsets.add(_end);
        _end += _dividerHeight;
      }
      for (final (i, p) in widget.segments[s].pages.indexed) {
        _items.add((s, i + 1));
        _offsets.add(_end);
        _end += width / _ratio(p);
      }
    }
    _laidOut = widget.segments.length;
    final start = (widget.startPage - 1).clamp(0, _items.length - 1);
    _scroll ??= ScrollController(initialScrollOffset: _offsets.isEmpty ? 0 : _offsets[start])..addListener(_onScroll);
  }

  void _onScroll() {
    // Página actual = la que ocupa el centro de la pantalla.
    final scroll = _scroll!;
    final center = scroll.offset + scroll.position.viewportDimension / 2;
    var item = 0;
    for (var i = 0; i < _offsets.length; i++) {
      if (_offsets[i] <= center) item = i;
    }
    var (segment, page) = _items[item];
    if (page == 0) (segment, page) = _items[item - 1]; // en el separador: aún el anterior
    widget.onPageChanged(segment, page);
    // Cerca del final del último libro: encadenar el siguiente.
    if (scroll.offset + scroll.position.viewportDimension * 4 >= _end) widget.onNearEnd();
  }

  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scroll?.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Desplaza una fracción de la altura de la pantalla (mando: trackpad y botones).
  void scrollByFraction(double fraction, {bool animate = false}) {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    final target = (scroll.offset + fraction * scroll.position.viewportDimension).clamp(
      0.0,
      scroll.position.maxScrollExtent,
    );
    if (animate) {
      scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      scroll.jumpTo(target);
    }
  }

  /// Inercia al soltar el dedo en el trackpad: [velocity] en pantallas por segundo.
  void fling(double velocity) {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients || velocity.abs() < 0.2) return;
    final distance = velocity * 0.35 * scroll.position.viewportDimension;
    final target = (scroll.offset + distance).clamp(0.0, scroll.position.maxScrollExtent);
    scroll.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.decelerate);
  }

  /// Teclado: flechas para avanzar poco, espacio/AvPág para casi una pantalla.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final viewport = scroll.position.viewportDimension;
    final double delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => viewport * 0.3,
      LogicalKeyboardKey.arrowUp => -viewport * 0.3,
      LogicalKeyboardKey.space || LogicalKeyboardKey.pageDown => viewport * 0.85,
      LogicalKeyboardKey.pageUp => -viewport * 0.85,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    final target = (scroll.offset + delta).clamp(0.0, scroll.position.maxScrollExtent);
    scroll.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    return KeyEventResult.handled;
  }

  /// Separador entre dos libros encadenados.
  Widget _divider(int segment) => SizedBox(
    height: _dividerHeight,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(gradient: Kofu.accentGradient, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 14),
        const Text('SIGUIENTE', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            widget.titles[segment],
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, _maxWidth);
        _layout(width);
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Center(
              child: SizedBox(
                width: width,
                child: ListView.builder(
                  controller: _scroll,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(3000),
                  itemCount: _items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == _items.length) {
                      return SizedBox(height: MediaQuery.sizeOf(context).height * 0.8, child: widget.endPage);
                    }
                    final (s, page) = _items[i];
                    if (page == 0) return _divider(s);
                    final segment = widget.segments[s];
                    final p = segment.pages[page - 1];
                    return SizedBox(
                      height: width / _ratio(p),
                      child: KomgaImage.provider(widget.image(p.number, segment), fit: BoxFit.fill, fade: false),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

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
import '../widgets/list_sheets.dart';

/// Lector de un libro, con paso al siguiente/anterior de la misma lista.
class ReaderScreen extends StatefulWidget {
  final Source source;
  final List<KomgaBook> books;
  final int initialIndex;

  const ReaderScreen({super.key, required this.source, required this.books, required this.initialIndex});

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

  KomgaBook get _book => widget.books[_index];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Que la pantalla no se apague mientras se lee.
    WakelockPlus.enable().catchError((_) {});
    _openBook(_index);
  }

  @override
  void dispose() {
    _flushProgress();
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
      if (pending != null) {
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
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Libro abierto desde disco (null = se lee de Komga).
  DownloadedBook? _local;

  /// Página a tamaño original (de disco o de Komga).
  ImageProvider _source(int page) {
    final local = _local;
    if (local != null) return FileImage(AppScope.read(context).downloads.pageFile(local, page));
    return NetworkImage(_client.pageUrl(_book.id, page), headers: _client.authHeaders);
  }

  /// Página descodificada al tamaño de la pantalla (x1.5 para tener margen al hacer zoom).
  /// Descodificar a tamaño completo ocupa ~20 MB por página y llena la caché enseguida.
  ImageProvider _image(int page) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_mode == ReadingMode.vertical) {
      final width = (size.width.clamp(0, 800) * dpr * 1.25).round();
      return ResizeImage(_source(page), width: width, allowUpscaling: false);
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
      body = _VerticalReader(
        key: ValueKey('v$_loadId'),
        image: _image,
        pages: _pages!,
        startPage: _startPage,
        onPageChanged: _onPageChanged,
        onTap: () => setState(() => _overlay = !_overlay),
        endPage: _chapterEnd(),
      );
    } else {
      final spreads = _useSpreads;
      body = _PagedReader(
        key: ValueKey('p$_loadId${_mode.name}$spreads'),
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          if (_overlay) ..._buildOverlay(context),
        ],
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
                  child: Text(
                    _book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
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
                IconButton(
                  tooltip: 'Añadir a lista',
                  onPressed: () => showAddToListSheet(context, [_book.snapshot(widget.source.id)]),
                  icon: const Icon(Icons.playlist_add_rounded, color: Colors.white),
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

class _VerticalReader extends StatefulWidget {
  final ImageProvider Function(int page) image;
  final List<KomgaPageInfo> pages;
  final int startPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTap;
  final Widget endPage; // fin de capítulo, al final del scroll

  const _VerticalReader({
    super.key,
    required this.image,
    required this.pages,
    required this.startPage,
    required this.onPageChanged,
    required this.onTap,
    required this.endPage,
  });

  @override
  State<_VerticalReader> createState() => _VerticalReaderState();
}

class _VerticalReaderState extends State<_VerticalReader> {
  static const _maxWidth = 800.0;
  static const _fallbackRatio = 0.7;
  ScrollController? _scroll;
  double _width = 0;
  List<double> _offsets = const []; // inicio de cada página

  double _ratio(KomgaPageInfo p) => p.aspectRatio ?? _fallbackRatio;

  void _layout(double width) {
    if (width == _width) return;
    _width = width;
    var acc = 0.0;
    _offsets = [for (final p in widget.pages) (acc += width / _ratio(p)) - width / _ratio(p)];
    _scroll ??= ScrollController(initialScrollOffset: _offsets[widget.startPage - 1])..addListener(_onScroll);
  }

  void _onScroll() {
    // Página actual = la que ocupa el centro de la pantalla.
    final center = _scroll!.offset + _scroll!.position.viewportDimension / 2;
    var page = 1;
    for (var i = 0; i < _offsets.length; i++) {
      if (_offsets[i] <= center) page = i + 1;
    }
    widget.onPageChanged(page);
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, _maxWidth);
        _layout(width);
        return GestureDetector(
          onTap: widget.onTap,
          child: Center(
            child: SizedBox(
              width: width,
              child: ListView.builder(
                controller: _scroll,
                scrollCacheExtent: const ScrollCacheExtent.pixels(3000),
                itemCount: widget.pages.length + 1,
                itemBuilder: (context, i) {
                  if (i == widget.pages.length) {
                    return SizedBox(height: MediaQuery.sizeOf(context).height * 0.8, child: widget.endPage);
                  }
                  final p = widget.pages[i];
                  return SizedBox(
                    height: width / _ratio(p),
                    child: KomgaImage.provider(widget.image(p.number), fit: BoxFit.fill, fade: false),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

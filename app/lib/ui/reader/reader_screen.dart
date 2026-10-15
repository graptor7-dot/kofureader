import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../../data/app_scope.dart';
import '../../data/app_state.dart';
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
    _openBook(_index);
  }

  @override
  void dispose() {
    _flushProgress();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _openBook(int index) async {
    _flushProgress();
    setState(() {
      _index = index;
      _pages = null;
      _error = null;
    });
    try {
      final book = widget.books[index];
      final results = await Future.wait([
        AppScope.read(context).effectiveMode(widget.source.id, book.libraryId, book.seriesId),
        _client.pages(book.id),
        // El progreso de la lista puede estar desfasado: se pide el libro de nuevo.
        _client.book(book.id),
      ]);
      if (!mounted || index != _index) return;
      final fresh = results[2] as KomgaBook;
      final pages = results[1] as List<KomgaPageInfo>;
      final start = fresh.inProgress ? fresh.readProgress!.page.clamp(1, pages.length) : 1;
      setState(() {
        _mode = results[0] as ReadingMode;
        _pages = pages;
        _page = start;
        _startPage = start;
        _loadId++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
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
    _client
        .markProgress(_book.id, page: page, completed: page >= pages.length)
        .catchError((_) {}); // sin conexión: no interrumpir la lectura
  }

  void _precache(int page) {
    final pages = _pages!;
    for (var p = page + 1; p <= page + 3 && p <= pages.length; p++) {
      precacheImage(NetworkImage(_client.pageUrl(_book.id, p), headers: _client.authHeaders), context);
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
        client: _client,
        book: _book,
        pages: _pages!,
        startPage: _startPage,
        onPageChanged: _onPageChanged,
        onTap: () => setState(() => _overlay = !_overlay),
        onEndReached: _nextBook,
      );
    } else {
      body = _PagedReader(
        key: ValueKey('p$_loadId${_mode.name}'),
        client: _client,
        book: _book,
        pages: _pages!,
        startPage: _page,
        rtl: _mode == ReadingMode.pagedRtl,
        onPageChanged: _onPageChanged,
        onCenterTap: () => setState(() => _overlay = !_overlay),
        onPastEnd: _nextBook,
        onBeforeStart: _prevBook,
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
// Modo páginas
// ---------------------------------------------------------------------------

class _PagedReader extends StatefulWidget {
  final KomgaClient client;
  final KomgaBook book;
  final List<KomgaPageInfo> pages;
  final int startPage;
  final bool rtl;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onCenterTap;
  final VoidCallback onPastEnd;
  final VoidCallback onBeforeStart;

  const _PagedReader({
    super.key,
    required this.client,
    required this.book,
    required this.pages,
    required this.startPage,
    required this.rtl,
    required this.onPageChanged,
    required this.onCenterTap,
    required this.onPastEnd,
    required this.onBeforeStart,
  });

  @override
  State<_PagedReader> createState() => _PagedReaderState();
}

class _PagedReaderState extends State<_PagedReader> {
  late final _controller = PageController(initialPage: widget.startPage - 1);
  final _focus = FocusNode();
  bool _zoomed = false;

  int get _current => (_controller.hasClients ? _controller.page?.round() : null) ?? widget.startPage - 1;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _next() {
    if (_current >= widget.pages.length - 1) {
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
              itemCount: widget.pages.length,
              onPageChanged: (i) => widget.onPageChanged(i + 1),
              itemBuilder: (context, i) => _ZoomablePage(
                url: widget.client.pageUrl(widget.book.id, widget.pages[i].number),
                headers: widget.client.authHeaders,
                onZoomChanged: (z) => setState(() => _zoomed = z),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePage({required this.url, required this.headers, required this.onZoomChanged});

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
        child: SizedBox.expand(
          child: KomgaImage(url: widget.url, headers: widget.headers, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modo vertical (webtoon)
// ---------------------------------------------------------------------------

class _VerticalReader extends StatefulWidget {
  final KomgaClient client;
  final KomgaBook book;
  final List<KomgaPageInfo> pages;
  final int startPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTap;
  final VoidCallback onEndReached;

  const _VerticalReader({
    super.key,
    required this.client,
    required this.book,
    required this.pages,
    required this.startPage,
    required this.onPageChanged,
    required this.onTap,
    required this.onEndReached,
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
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: FilledButton.icon(
                          onPressed: widget.onEndReached,
                          icon: const Icon(Icons.skip_next),
                          label: const Text('Siguiente libro'),
                        ),
                      ),
                    );
                  }
                  final p = widget.pages[i];
                  return SizedBox(
                    height: width / _ratio(p),
                    child: KomgaImage(
                      url: widget.client.pageUrl(widget.book.id, p.number),
                      headers: widget.client.authHeaders,
                      fit: BoxFit.fill,
                    ),
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

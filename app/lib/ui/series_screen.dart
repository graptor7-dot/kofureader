import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/snapshots.dart';
import '../data/source.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'reader/reader_screen.dart';
import 'widgets/cover_card.dart';
import 'widgets/list_sheets.dart';
import 'widgets/reading_mode_picker.dart';
import 'widgets/selection.dart';

/// Ficha de una serie y sus libros.
class SeriesScreen extends StatefulWidget {
  final Source source;
  final String seriesId;
  final KomgaSeries? initial;

  const SeriesScreen({super.key, required this.source, required this.seriesId, this.initial});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  late KomgaSeries? _series = widget.initial;
  List<KomgaBook>? _books;
  String? _error;
  final Set<ReadStatus> _status = {};
  final _selection = SelectionController<KomgaBook>();

  String get _sourceId => widget.source.id;

  @override
  void initState() {
    super.initState();
    _selection.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = AppScope.read(context).client(_sourceId);
    try {
      final results = await Future.wait([client.seriesById(widget.seriesId), client.books(widget.seriesId)]);
      if (!mounted) return;
      setState(() {
        _series = results[0] as KomgaSeries;
        _books = results[1] as List<KomgaBook>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<KomgaBook> get _visible => _status.isEmpty ? _books! : _books!.where((b) => _status.contains(b.status)).toList();

  Future<void> _open(KomgaBook book) async {
    final books = _books!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(source: widget.source, books: books, initialIndex: books.indexOf(book)),
      ),
    );
    if (mounted) _load();
  }

  /// Primer libro empezado; si no, el primero sin leer; si no, el primero.
  KomgaBook _continueBook(List<KomgaBook> books) =>
      books.where((b) => b.inProgress).firstOrNull ?? books.where((b) => !b.isRead).firstOrNull ?? books.first;

  void _random() {
    final pool = _selection.active ? _selection.values : _visible;
    if (pool.isEmpty) {
      showToast(context, 'No hay libros con estos filtros', icon: Icons.info_outline);
      return;
    }
    _selection.clear();
    _open(pickRandom(pool));
  }

  Future<void> _pickMode() async {
    final state = AppScope.read(context);
    final r = await showReadingModePickerRaw(
      context,
      title: 'Modo de lectura de esta serie',
      current: state.seriesModeOverride(_sourceId, widget.seriesId),
      allowInherit: true,
    );
    if (r == inheritModeSentinel) {
      state.setSeriesMode(_sourceId, widget.seriesId, null);
    } else if (r is ReadingMode) {
      state.setSeriesMode(_sourceId, widget.seriesId, r);
    }
  }

  void _favoriteSelected() {
    final data = AppScope.read(context).data;
    data.addAll(data.favorites.id, _selection.values.map((b) => b.snapshot(_sourceId)));
    showToast(context, '${_selection.count} añadidos a Favoritos');
    _selection.clear();
  }

  Future<void> _addSelectedToList() async {
    await showAddToListSheet(context, _selection.values.map((b) => b.snapshot(_sourceId)).toList());
    _selection.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final books = _books;
    return PopScope(
      canPop: !_selection.active,
      onPopInvokedWithResult: (didPop, _) => _selection.clear(),
      child: Scaffold(
        floatingActionButton: books == null || books.isEmpty
            ? null
            : RandomFab(onPressed: _random, selectedCount: _selection.count),
        appBar: _selection.active
            ? SelectionBar(
                count: _selection.count,
                onClose: _selection.clear,
                onSelectAll: () => _selection.selectAll({for (final b in _visible) b.id: b}),
                actions: [
                  IconButton(
                    tooltip: 'Añadir a Favoritos',
                    onPressed: _favoriteSelected,
                    icon: const Icon(Icons.favorite_border_rounded),
                  ),
                  IconButton(
                    tooltip: 'Añadir a lista',
                    onPressed: _addSelectedToList,
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                ],
              )
            : null,
        body: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              if (!_selection.active) _header(state),
              if (_error != null && books == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(onPressed: _load, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              else if (books == null)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else ...[
                SliverToBoxAdapter(
                  child: FilterRow(
                    children: [
                      for (final s in ReadStatus.values)
                        FilterChip(
                          label: Text('${s.label} · ${books.where((b) => b.status == s).length}'),
                          selected: _status.contains(s),
                          onSelected: (_) => setState(() => _status.contains(s) ? _status.remove(s) : _status.add(s)),
                        ),
                    ],
                  ),
                ),
                _booksGrid(state),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _booksGrid(AppState state) {
    final client = state.client(_sourceId);
    final visible = _visible;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      sliver: SliverGrid.builder(
        gridDelegate: coverGridDelegate,
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final b = visible[i];
          return CoverCard(
            imageUrl: client.bookThumbnailUrl(b.id),
            headers: client.authHeaders,
            title: b.title,
            subtitle: b.inProgress ? 'Pág. ${b.readProgress!.page} de ${b.pagesCount}' : '${b.pagesCount} páginas',
            read: b.isRead,
            progress: b.inProgress ? b.progressFraction : 0,
            favorite: state.data.isFavorite(b.snapshot(_sourceId).ref),
            selected: _selection.contains(b.id),
            selectionActive: _selection.active,
            onTap: _selection.active ? () => _selection.toggle(b.id, b) : () => _open(b),
            onLongPress: () => _selection.toggle(b.id, b),
          );
        },
      ),
    );
  }

  Widget _header(AppState state) {
    final client = state.client(_sourceId);
    final series = _series;
    final books = _books;
    final thumb = client.seriesThumbnailUrl(widget.seriesId);
    final snap = series?.snapshot(_sourceId);
    final favorite = snap != null && state.data.isFavorite(snap.ref);
    final override = state.seriesModeOverride(_sourceId, widget.seriesId);
    final libName = series == null ? null : state.libraryName(_sourceId, series.libraryId);
    final width = MediaQuery.sizeOf(context).width;
    final coverWidth = width < 600 ? 120.0 : 160.0;

    return SliverAppBar(
      pinned: true,
      expandedHeight: coverWidth * 1.45 + kToolbarHeight + 40,
      title: Text(series?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Modo de lectura',
          onPressed: _pickMode,
          icon: Icon(Icons.chrome_reader_mode_rounded, color: override != null ? Kofu.accent : null),
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Fondo: portada desenfocada.
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Opacity(
                opacity: 0.55,
                child: KomgaImage(url: thumb, headers: client.authHeaders),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x660C0C11), Kofu.background],
                  stops: [0, 0.95],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, kToolbarHeight + 4, 20, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: coverWidth,
                      height: coverWidth * 1.45,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Kofu.radius),
                        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, 10))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Kofu.radius),
                        child: KomgaImage(url: thumb, headers: client.authHeaders),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SourceChip(
                            label: [widget.source.name, ?libName].join(' · '),
                            color: state.sourceColor(_sourceId),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            series?.title ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: width < 600 ? 22 : 28,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (series != null)
                            Text(
                              '${series.booksCount} libros · ${series.booksReadCount} leídos'
                              '${override != null ? ' · ${override.label}' : ''}',
                              style: const TextStyle(color: Kofu.muted, fontSize: 13),
                            ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              if (books != null && books.isNotEmpty)
                                Flexible(
                                  child: FilledButton.icon(
                                    onPressed: () => _open(_continueBook(books)),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: Text(
                                      _continueBook(books).inProgress ? 'Continuar' : 'Leer',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              _RoundAction(
                                tooltip: favorite ? 'Quitar de Favoritos' : 'Añadir a Favoritos',
                                icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: favorite ? Kofu.accent : null,
                                onTap: snap == null ? null : () => state.data.toggleFavorite(snap),
                              ),
                              const SizedBox(width: 8),
                              _RoundAction(
                                tooltip: 'Añadir a lista',
                                icon: Icons.playlist_add_rounded,
                                onTap: snap == null ? null : () => showAddToListSheet(context, [snap]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const _RoundAction({required this.tooltip, required this.icon, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: const CircleBorder(side: BorderSide(color: Kofu.outline)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(icon, key: ValueKey(icon), color: color),
            ),
          ),
        ),
      ),
    );
  }
}

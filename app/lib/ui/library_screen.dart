import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/snapshots.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'navigation.dart';
import 'widgets/cover_card.dart';
import 'widgets/list_sheets.dart';
import 'widgets/reading_mode_picker.dart';
import 'widgets/selection.dart';

/// Rejilla de series de una biblioteca, con búsqueda, filtros y carga progresiva.
class LibraryScreen extends StatefulWidget {
  final LibraryEntry entry;

  const LibraryScreen({super.key, required this.entry});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _items = <KomgaSeries>[];
  final _scroll = ScrollController();
  final _selection = SelectionController<KomgaSeries>();
  int _nextPage = 0;
  int _total = 0;
  bool _last = false;
  bool _loading = false;
  bool _randomBusy = false;
  String? _error;
  String _search = '';
  SeriesSort _sort = SeriesSort.title;
  final Set<ReadStatus> _status = {};
  Timer? _debounce;
  int _generation = 0; // descarta respuestas de consultas anteriores

  String get _sourceId => widget.entry.source.id;

  @override
  void initState() {
    super.initState();
    _selection.addListener(() => setState(() {}));
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _selection.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || _last) return;
    setState(() => _loading = true);
    final gen = _generation;
    try {
      final page = await AppScope.read(context)
          .client(_sourceId)
          .series(
            libraryId: widget.entry.library.id,
            page: _nextPage,
            search: _search,
            sort: _sort,
            readStatus: _status,
          );
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page.content);
        _total = page.totalElements;
        _last = page.last;
        _nextPage++;
        _error = null;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e.toString());
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
    // Si la primera página no llena la pantalla, seguir cargando.
    if (mounted && !_last && _error == null && _scroll.hasClients && _scroll.position.maxScrollExtent == 0) {
      _loadMore();
    }
  }

  Future<void> _reset() async {
    setState(() {
      _generation++;
      _items.clear();
      _nextPage = 0;
      _last = false;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = text.trim();
      _reset();
    });
  }

  void _toggleStatus(ReadStatus s) {
    setState(() => _status.contains(s) ? _status.remove(s) : _status.add(s));
    _reset();
  }

  Future<void> _pickMode() async {
    final state = AppScope.read(context);
    final library = widget.entry.library;
    final mode = await showReadingModePicker(
      context,
      title: 'Modo por defecto de ${library.name}',
      current: state.libraryMode(_sourceId, library),
    );
    if (mode != null) state.setLibraryMode(_sourceId, library.id, mode);
  }

  Future<void> _open(KomgaSeries s) async {
    await openSeries(context, widget.entry.source, s.id, series: s);
  }

  /// Aleatorio: entre lo seleccionado o entre todo lo que cumple los filtros.
  Future<void> _random() async {
    if (_selection.active) {
      final pick = pickRandom(_selection.values);
      _selection.clear();
      await _open(pick);
      return;
    }
    setState(() => _randomBusy = true);
    try {
      final client = AppScope.read(context).client(_sourceId);
      final libraryId = widget.entry.library.id;
      final total = await client.seriesCount(libraryId: libraryId, search: _search, readStatus: _status);
      if (total == 0) {
        if (mounted) showToast(context, 'No hay series con estos filtros', icon: Icons.info_outline);
        return;
      }
      final s = await client.seriesAt(
        random.nextInt(total),
        libraryId: libraryId,
        search: _search,
        readStatus: _status,
      );
      if (s != null && mounted) await _open(s);
    } catch (e) {
      if (mounted) showToast(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _randomBusy = false);
    }
  }

  void _favoriteSelected() {
    final data = AppScope.read(context).data;
    data.addAll(data.favorites.id, _selection.values.map((s) => s.snapshot(_sourceId)));
    showToast(context, '${_selection.count} añadidas a Favoritos');
    _selection.clear();
  }

  Future<void> _addSelectedToList() async {
    await showAddToListSheet(context, _selection.values.map((s) => s.snapshot(_sourceId)).toList());
    _selection.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final client = state.client(_sourceId);
    final color = state.sourceColor(_sourceId);
    return PopScope(
      canPop: !_selection.active,
      onPopInvokedWithResult: (didPop, _) => _selection.clear(),
      child: Scaffold(
        floatingActionButton: RandomFab(onPressed: _random, busy: _randomBusy, selectedCount: _selection.count),
        appBar: _selection.active
            ? SelectionBar(
                count: _selection.count,
                onClose: _selection.clear,
                onSelectAll: () => _selection.selectAll({for (final s in _items) s.id: s}),
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
          onRefresh: _reset,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (!_selection.active)
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 120,
                  actions: [
                    PopupMenuButton<SeriesSort>(
                      tooltip: 'Ordenar',
                      icon: const Icon(Icons.sort_rounded),
                      initialValue: _sort,
                      onSelected: (s) {
                        _sort = s;
                        _reset();
                      },
                      itemBuilder: (_) => [
                        for (final s in SeriesSort.values) PopupMenuItem(value: s, child: Text(s.label)),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Modo de lectura',
                      onPressed: _pickMode,
                      icon: const Icon(Icons.chrome_reader_mode_rounded),
                    ),
                    const SizedBox(width: 8),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14, end: 120),
                    title: Text(
                      widget.entry.library.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    background: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-1, -1),
                          radius: 1.6,
                          colors: [color.withValues(alpha: 0.22), Kofu.background],
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    onChanged: _onSearch,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar series',
                      isDense: true,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: FilterRow(
                  children: [
                    for (final s in ReadStatus.values)
                      FilterChip(
                        label: Text(s.label),
                        selected: _status.contains(s),
                        onSelected: (_) => _toggleStatus(s),
                      ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(
                    _loading && _items.isEmpty ? '' : '$_total series · ${_sort.label}',
                    style: const TextStyle(color: Kofu.muted, fontSize: 12),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                sliver: SliverGrid.builder(
                  gridDelegate: coverGridDelegate,
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final s = _items[i];
                    final snap = s.snapshot(_sourceId);
                    return CoverCard(
                      imageUrl: client.seriesThumbnailUrl(s.id),
                      headers: client.authHeaders,
                      title: s.title,
                      subtitle: '${s.booksCount} libro${s.booksCount == 1 ? '' : 's'}',
                      badge: s.booksUnreadCount > 0 && s.booksReadCount > 0 ? '${s.booksUnreadCount}' : null,
                      read: s.booksCount > 0 && s.booksUnreadCount == 0,
                      progress: s.booksCount > 0 ? s.booksReadCount / s.booksCount : 0,
                      favorite: state.data.isFavorite(snap.ref),
                      selected: _selection.contains(s.id),
                      selectionActive: _selection.active,
                      onTap: _selection.active ? () => _selection.toggle(s.id, s) : () => _open(s),
                      onLongPress: () => _selection.toggle(s.id, s),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                  child: Center(
                    child: _error != null
                        ? Column(
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              TextButton(onPressed: _loadMore, child: const Text('Reintentar')),
                            ],
                          )
                        : _loading
                        ? const CircularProgressIndicator()
                        : _items.isEmpty
                        ? const Text('Sin resultados', style: TextStyle(color: Kofu.muted))
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

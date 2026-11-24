import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/snapshots.dart';
import '../data/user_data.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'tag_search_screen.dart';
import 'widgets/manage.dart';
import 'extras_screens.dart';
import 'list_screen.dart';
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

  // Modo gestión (solo en el PC): botón grande por obra con acciones, y borrar del servidor.

  // Modos locales (sin pedir a Komga): obras valoradas o con una etiqueta.
  bool _rated = false;
  String? _tag;
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

  /// Marca las series seleccionadas (todos sus libros) como leídas o no leídas en Komga.
  Future<void> _setSelectedRead(bool read) async {
    final series = _selection.values;
    final client = AppScope.read(context).client(_sourceId);
    _selection.clear();
    try {
      await Future.wait(series.map((s) => client.setSeriesRead(s.id, read)));
      if (mounted) {
        showToast(
          context,
          '${series.length} serie${series.length == 1 ? '' : 's'} marcada${series.length == 1 ? '' : 's'} '
          'como ${read ? 'leída' : 'no leída'}${series.length == 1 ? '' : 's'}',
          icon: read ? Icons.done_all_rounded : Icons.remove_done_rounded,
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '$e', icon: Icons.error_outline);
    }
    await _reset();
  }

  /// Rejilla de obras valoradas o etiquetadas de esta biblioteca (datos locales).
  Widget _localGrid(AppState state) {
    final libraryId = widget.entry.library.id;
    final items = _rated
        ? [for (final (s, r) in state.extras.rated(sourceId: _sourceId, libraryId: libraryId)) (s, r)]
        : [
            for (final s in state.extras.tagged(_tag!, sourceId: _sourceId, libraryId: libraryId))
              (s, state.extras.rating(s.ref)),
          ];
    final client = state.client(_sourceId);
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text(
              _rated ? 'Aún no has valorado nada aquí' : 'Nada con esta etiqueta en esta biblioteca',
              style: const TextStyle(color: Kofu.muted),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      sliver: CoverSliverGrid(
        itemCount: items.length,
        itemBuilder: (context, i) {
          final (item, stars) = items[i];
          return CoverCard(
            imageUrl: client.thumbnailUrl(item.ref),
            headers: client.authHeaders,
            title: item.title,
            subtitle: [if (stars > 0) '★$stars', ?item.seriesTitle].join(' · '),
            kindIcon: item.ref.kind == ItemKind.book ? Icons.menu_book_rounded : null,
            onTap: () => openSnapshot(context, item),
          );
        },
      ),
    );
  }

  // ---- Modo gestión ----

  String _plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

  Future<void> _deleteSeries(List<KomgaSeries> series) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40),
        title: Text(
          '¿Borrar ${series.length == 1 ? '"${series.first.title}"' : _plural(series.length, 'obra')} del servidor?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se borrarán sus archivos del NAS. No se puede deshacer.'),
            if (series.length > 1) ...[
              const SizedBox(height: 12),
              for (final s in series.take(8)) Text('• ${s.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
              if (series.length > 8) Text('… y ${series.length - 8} más', style: const TextStyle(color: Kofu.muted)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final state = AppScope.read(context);
    final client = state.client(_sourceId);
    _selection.clear();
    var done = 0;
    String? error;
    for (final s in series) {
      try {
        await client.deleteSeriesFiles(s.id);
        done++;
        // Komga la sigue listando hasta que escanea y vacía la papelera: se marca como borrada.
        state.markGone(_sourceId, s.id, 'series');
        if (mounted) setState(() {});
      } catch (e) {
        error = '$e';
        break; // si falla una (p. ej. sin permiso), no seguir
      }
    }
    if (!mounted) return;
    showToast(
      context,
      error ?? '${_plural(done, 'obra')} borrada${done == 1 ? '' : 's'} del servidor',
      icon: error == null ? Icons.delete_forever_rounded : Icons.error_outline,
    );
    if (done > 0) client.scanLibrary(series.first.libraryId).catchError((_) {});
  }

  /// Marca como revisados los autores elegidos (o les quita la marca si ya lo estaban todos).
  void _toggleSelectedReviewed() {
    final state = AppScope.read(context);
    final series = _selection.values;
    final on = !series.every((s) => state.isReviewed(_sourceId, s.id));
    for (final s in series) {
      state.setReviewed(_sourceId, s.id, on);
    }
    showToast(
      context,
      series.length == 1
          ? (on ? 'Autor marcado como revisado' : 'Autor sin marcar')
          : (on ? '${series.length} autores marcados como revisados' : '${series.length} autores sin marcar'),
      icon: Icons.verified_rounded,
    );
    _selection.clear();
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
                  PopupMenuButton<bool>(
                    tooltip: 'Leído / no leído',
                    icon: const Icon(Icons.done_all_rounded),
                    onSelected: _setSelectedRead,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('Marcar series como leídas')),
                      PopupMenuItem(value: false, child: Text('Marcar series como no leídas')),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Etiquetas',
                    onPressed: () async {
                      await showTagsSheet(context, _selection.values.map((s) => s.snapshot(_sourceId)).toList());
                      _selection.clear();
                    },
                    icon: const Icon(Icons.sell_rounded),
                  ),
                  IconButton(
                    tooltip: 'Añadir al Top 10',
                    onPressed: () async {
                      for (final s in _selection.values) {
                        await addToTop10(context, s.snapshot(_sourceId));
                      }
                      _selection.clear();
                    },
                    icon: const Icon(Icons.emoji_events_rounded, color: Kofu.gold),
                  ),
                  if (state.manageMode)
                    IconButton(
                      tooltip: 'Marcar / quitar revisado',
                      onPressed: _toggleSelectedReviewed,
                      icon: const Icon(Icons.verified_rounded, color: Kofu.reviewed),
                    ),
                  if (state.manageMode)
                    IconButton(
                      tooltip: 'Borrar del servidor',
                      onPressed: () => _deleteSeries(_selection.values),
                      icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
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
                    IconButton(
                      tooltip: 'Buscar capítulos por tags',
                      icon: const Icon(Icons.label_rounded),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TagSearchScreen(entry: widget.entry)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Favoritos de esta biblioteca',
                      icon: const Icon(Icons.favorite_rounded, color: Kofu.accent),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ListScreen(
                            listId: UserData.favoritesId,
                            library: (
                              sourceId: _sourceId,
                              libraryId: widget.entry.library.id,
                              name: widget.entry.library.name,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Top 10 de esta biblioteca',
                      icon: const Icon(Icons.emoji_events_rounded, color: Kofu.gold),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Top10Screen(initialLibrary: '$_sourceId|${widget.entry.library.id}'),
                        ),
                      ),
                    ),
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
              if (state.manageMode)
                const SliverToBoxAdapter(
                  child: ManageBanner(
                    text: 'Modo gestión activo: marca cada autor como revisado, o entra para gestionar sus capítulos.',
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
                    FilterChip(
                      avatar: const Icon(Icons.star_rounded, size: 16, color: Kofu.gold),
                      label: const Text('Mis valoradas'),
                      selected: _rated,
                      onSelected: (v) => setState(() {
                        _rated = v;
                        if (v) _tag = null;
                      }),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: TagFilterRow(
                  selected: _tag,
                  onSelected: (t) => setState(() {
                    _tag = t;
                    if (t != null) _rated = false;
                  }),
                ),
              ),
              if (_rated || _tag != null) _localGrid(state),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(
                    _loading && _items.isEmpty ? '' : '$_total series · ${_sort.label}',
                    style: const TextStyle(color: Kofu.muted, fontSize: 12),
                  ),
                ),
              ),
              if (!_rated && _tag == null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  sliver: CoverSliverGrid(
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final s = _items[i];
                      final snap = s.snapshot(_sourceId);
                      final card = CoverCard(
                        imageUrl: client.seriesThumbnailUrl(s.id),
                        headers: client.authHeaders,
                        title: s.title,
                        gone: state.isGone(_sourceId, s.id),
                        reviewed: state.manageMode && state.isReviewed(_sourceId, s.id),
                        actions: state.manageMode && !_selection.active && !state.isGone(_sourceId, s.id)
                            ? ManageReviewAction(
                                reviewed: state.isReviewed(_sourceId, s.id),
                                onToggle: () => state.setReviewed(_sourceId, s.id, !state.isReviewed(_sourceId, s.id)),
                              )
                            : null,
                        subtitle: [
                          if (state.extras.rating(snap.ref) > 0) '★${state.extras.rating(snap.ref)}',
                          '${s.booksCount} libro${s.booksCount == 1 ? '' : 's'}',
                        ].join(' · '),
                        badge: s.booksUnreadCount > 0 && s.booksReadCount > 0 ? '${s.booksUnreadCount}' : null,
                        read: s.booksCount > 0 && s.booksUnreadCount == 0,
                        progress: s.booksCount > 0 ? s.booksReadCount / s.booksCount : 0,
                        favorite: state.data.isFavorite(snap.ref),
                        selected: _selection.contains(s.id),
                        selectionActive: _selection.active,
                        onTap: _selection.active
                            ? () => _selection.toggle(s.id, s)
                            : state.isGone(_sourceId, s.id)
                            ? () => showToast(
                                context,
                                'Esta obra ya no está en el servidor',
                                icon: Icons.delete_forever_rounded,
                              )
                            : () => _open(s),
                        onLongPress: () => _selection.toggle(s.id, s),
                      );
                      return card;
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

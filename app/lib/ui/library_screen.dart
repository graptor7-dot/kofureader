import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/snapshots.dart';
import '../data/user_data.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'desktop.dart' show isDesktop;
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
  bool _manage = false;

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
      sliver: SliverGrid.builder(
        gridDelegate: coverGridDelegate,
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

  /// Acciones de gestión sobre una obra o sobre la selección.
  Future<void> _manageSheet(List<KomgaSeries> series) async {
    final one = series.length == 1;
    final title = one ? series.first.title : '${_plural(series.length, 'obra')} seleccionadas';
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.done_all_rounded),
              title: const Text('Marcar como leída'),
              onTap: () => Navigator.pop(ctx, 'read'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_done_rounded),
              title: const Text('Marcar como no leída'),
              onTap: () => Navigator.pop(ctx, 'unread'),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_rounded, color: Kofu.accent),
              title: const Text('Añadir a Favoritos'),
              onTap: () => Navigator.pop(ctx, 'fav'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Añadir a lista'),
              onTap: () => Navigator.pop(ctx, 'list'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              title: const Text('Borrar del servidor', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Borra los archivos del NAS. No se puede deshacer.'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final data = AppScope.read(context).data;
    switch (action) {
      case 'read' || 'unread':
        _selection.selectAll({for (final s in series) s.id: s});
        await _setSelectedRead(action == 'read');
      case 'fav':
        data.addAll(data.favorites.id, series.map((s) => s.snapshot(_sourceId)));
        showToast(context, '${_plural(series.length, 'obra')} en Favoritos', icon: Icons.favorite_rounded);
        _selection.clear();
      case 'list':
        await showAddToListSheet(context, series.map((s) => s.snapshot(_sourceId)).toList());
        _selection.clear();
      case 'delete':
        await _deleteSeries(series);
    }
  }

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
    final client = AppScope.read(context).client(_sourceId);
    _selection.clear();
    var done = 0;
    String? error;
    for (final s in series) {
      try {
        await client.deleteSeriesFiles(s.id);
        done++;
        if (mounted) setState(() => _items.removeWhere((x) => x.id == s.id));
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
    if (done > 0) _total -= done;
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
                  if (_manage)
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
                    if (isDesktop)
                      IconButton(
                        tooltip: _manage ? 'Salir del modo gestión' : 'Modo gestión',
                        onPressed: () => setState(() => _manage = !_manage),
                        icon: Icon(Icons.admin_panel_settings_rounded, color: _manage ? Colors.redAccent : null),
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
              if (_manage)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(Kofu.radius),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings_rounded, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Modo gestión: pulsa «Gestionar» en una obra, o mantén pulsadas varias para actuar en masa.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        TextButton(onPressed: () => setState(() => _manage = false), child: const Text('Salir')),
                      ],
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
                  sliver: SliverGrid.builder(
                    gridDelegate: coverGridDelegate,
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final s = _items[i];
                      final snap = s.snapshot(_sourceId);
                      final card = CoverCard(
                        imageUrl: client.seriesThumbnailUrl(s.id),
                        headers: client.authHeaders,
                        title: s.title,
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
                        onTap: _selection.active ? () => _selection.toggle(s.id, s) : () => _open(s),
                        onLongPress: () => _selection.toggle(s.id, s),
                      );
                      if (!_manage || _selection.active) return card;
                      return Stack(
                        children: [
                          card,
                          Positioned.fill(
                            bottom: 48, // sobre la portada, no sobre el título
                            child: Center(child: _ManageButton(onPressed: () => _manageSheet([s]))),
                          ),
                        ],
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

/// Botón grande de "Gestionar" sobre cada obra en el modo gestión.
class _ManageButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ManageButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: 0.75),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
    ),
    icon: const Icon(Icons.tune_rounded),
    label: const Text('Gestionar'),
  );
}

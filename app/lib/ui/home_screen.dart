import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/cover_cache.dart';
import '../data/extras.dart';
import '../data/novels.dart';
import '../data/user_data.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'downloads_screen.dart';
import 'extras_screens.dart';
import 'novels/novel_reader_screen.dart';
import 'stats_screen.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'novels/novel_library_screen.dart';
import 'list_screen.dart';
import 'navigation.dart';
import 'desktop.dart' show isDesktop;
import 'remote_screen.dart';
import 'search_screen.dart';
import 'sources_screen.dart';
import 'widgets/cover_card.dart';
import 'widgets/list_sheets.dart';
import 'widgets/selection.dart';
import 'widgets/update_widgets.dart';

/// Algo seleccionable en el inicio: una biblioteca o una lista.
sealed class _HomePick {}

class _LibraryPick extends _HomePick {
  final LibraryEntry entry;
  _LibraryPick(this.entry);
}

class _ListPick extends _HomePick {
  final UserList list;
  _ListPick(this.list);
}

/// Los Favoritos de una biblioteca.
class _FavPick extends _HomePick {
  final LibraryEntry entry;
  _FavPick(this.entry);
}

/// Pantalla inicial: seguir leyendo, bibliotecas de todos los servidores y listas.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<List<SourceLibraries>>? _libraries;
  Future<List<SourcedBook>>? _continue;
  Future<List<SourcedBook>>? _upNext;
  Future<({List<NovelProgress> reading, List<NovelProgress> upNext})>? _novelProgress;
  Future<int>? _newsCount;
  Future<List<NovelLibrary>>? _novelLibs;
  List<NovelLibrary> _novelLibList = const [];
  Future<List<NovelWork>>? _novelPreview;
  final _previews = <String, Future<List<KomgaSeries>>>{};
  final _selection = SelectionController<_HomePick>();
  int _sourcesSignature = -1;
  bool _randomBusy = false;

  @override
  void initState() {
    super.initState();
    _selection.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recarga cuando cambian los servidores configurados.
    final state = AppScope.of(context);
    final signature = Object.hashAll(
      state.sources.map((s) => '${s.id}${s.baseUrl}${s.authType}${state.hasSecret(s.id)}'),
    );
    if (signature != _sourcesSignature) {
      _sourcesSignature = signature;
      _load(refresh: true);
    }
  }

  void _load({bool refresh = false}) {
    final state = AppScope.read(context);
    _previews.clear();
    _libraries = state.loadAllLibraries(refresh: refresh);
    _continue = state.continueReading();
    _upNext = state.upNext();
    _novelProgress = state.novels.progress().catchError((_) => (reading: <NovelProgress>[], upNext: <NovelProgress>[]));
    _newsCount = state
        .news()
        .then((n) => n.where((b) => (b.book.created ?? DateTime(0)).isAfter(state.newsSeenAt)).length)
        .catchError((_) => 0);
    _novelPreview = null;
    _novelLibs = state.novels.available
        ? state.novels.libraries().catchError((_) => <NovelLibrary>[])
        : Future.value(const <NovelLibrary>[]);
    _novelLibs!.then((libs) {
      if (mounted) setState(() => _novelLibList = libs);
    });
  }

  Future<void> _reload() async {
    await AppScope.read(context).sync.syncNow();
    if (!mounted) return;
    setState(() => _load(refresh: true));
    await Future.wait([_libraries!, _continue!]);
  }

  void _refreshContinue() {
    if (!mounted) return;
    final state = AppScope.read(context);
    setState(() {
      _continue = state.continueReading();
      _upNext = state.upNext();
      _novelProgress = state.novels.progress().catchError(
        (_) => (reading: <NovelProgress>[], upNext: <NovelProgress>[]),
      );
    });
  }

  Future<List<KomgaSeries>> _preview(LibraryEntry e) => _previews.putIfAbsent(
    e.key,
    () =>
        AppScope.read(context)
            .client(e.source.id)
            .series(libraryId: e.library.id, size: 4, sort: SeriesSort.added)
            .then((p) => p.content)
            .catchError((_) => <KomgaSeries>[]),
  );

  /// Bibliotecas cargadas que no están ocultas.
  List<LibraryEntry> _visibleLibraries(List<SourceLibraries> groups) {
    final state = AppScope.read(context);
    return [
      for (final g in groups)
        for (final e in g.libraries)
          if (!state.isLibraryHidden(e.source.id, e.library.id)) e,
    ];
  }

  Future<void> _openComplete() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ListScreen(listId: UserData.completeId)));
    _refreshContinue();
  }

  /// Fila de portadas de las ediciones completas (solo si hay alguna).
  Widget _completeSection(AppState state) {
    final items = state.visibleItemsOf(UserData.completeId);
    if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 12, 14),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, color: Kofu.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ediciones completas',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(onPressed: _openComplete, child: const Text('Ver todas')),
              ],
            ),
          ),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final item = items[i].item;
                final client = state.client(item.ref.sourceId);
                return SizedBox(
                  width: 140,
                  child: CoverCard(
                    imageUrl: client.thumbnailUrl(item.ref),
                    headers: client.authHeaders,
                    title: item.seriesTitle ?? item.title,
                    subtitle: item.title,
                    complete: true,
                    sourceColor: state.sourceColor(item.ref.sourceId),
                    onTap: () => openSnapshot(context, item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHistory() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
    _refreshContinue();
  }

  void _openSources() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesScreen()));

  // ---- Aleatorio ----

  Future<void> _random(List<SourceLibraries> groups) async {
    final state = AppScope.read(context);
    final picks = _selection.active ? _selection.values : [for (final e in _visibleLibraries(groups)) _LibraryPick(e)];
    if (picks.isEmpty) return;
    setState(() => _randomBusy = true);
    try {
      // Cuántos elementos aporta cada origen, para que todos pesen por igual.
      final counts = await Future.wait(
        picks.map((p) async {
          try {
            return switch (p) {
              _LibraryPick(:final entry) =>
                await state.client(entry.source.id).seriesCount(libraryId: entry.library.id),
              _ListPick(:final list) => state.visibleItemsOf(list.id).length,
              _FavPick(:final entry) => state.favoritesOf(entry.source.id, entry.library.id).length,
            };
          } catch (_) {
            return 0; // servidor sin conexión: no participa
          }
        }),
      );
      final total = counts.fold(0, (a, b) => a + b);
      if (total == 0) {
        if (mounted) showToast(context, 'No hay nada para elegir', icon: Icons.info_outline);
        return;
      }
      var r = random.nextInt(total);
      var i = 0;
      while (r >= counts[i]) {
        r -= counts[i];
        i++;
      }
      if (!mounted) return;
      switch (picks[i]) {
        case _LibraryPick(:final entry):
          final series = await state.client(entry.source.id).seriesAt(r, libraryId: entry.library.id);
          if (series != null && mounted) await openSeries(context, entry.source, series.id, series: series);
        case _ListPick(:final list):
          await openSnapshot(context, state.visibleItemsOf(list.id)[r].item);
        case _FavPick(:final entry):
          await openSnapshot(context, state.favoritesOf(entry.source.id, entry.library.id)[r].item);
      }
      _refreshContinue();
    } catch (e) {
      if (mounted) showToast(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _randomBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.sources.isEmpty) return _Welcome(onAdd: _openSources);

    return FutureBuilder<List<SourceLibraries>>(
      future: _libraries,
      builder: (context, snap) {
        final groups = snap.data;
        return PopScope(
          canPop: !_selection.active,
          onPopInvokedWithResult: (didPop, _) => _selection.clear(),
          child: Scaffold(
            appBar: _selection.active ? SelectionBar(count: _selection.count, onClose: _selection.clear) : null,
            floatingActionButton: groups == null
                ? null
                : RandomFab(busy: _randomBusy, selectedCount: _selection.count, onPressed: () => _random(groups)),
            body: RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                slivers: [
                  if (!_selection.active) _header(),
                  const SliverToBoxAdapter(child: UpdateBanner()),
                  if (state.remote.castTarget != null) const SliverToBoxAdapter(child: _CastBanner()),
                  // Secciones en el orden elegido en Ajustes → Personalizar inicio.
                  for (final (section, visible) in state.extras.homeLayout)
                    if (visible) ..._section(section, state, groups),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header() {
    return SliverAppBar(
      floating: true,
      toolbarHeight: 72,
      titleSpacing: 20,
      title: ShaderMask(
        shaderCallback: (r) => Kofu.accentGradient.createShader(r),
        child: const Text(
          'KofuReader',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
        ),
      ),
      actions: [
        if (AppScope.of(context).hasPrivateLibraries)
          Builder(
            builder: (context) {
              final state = AppScope.of(context);
              final hidden = state.privateHidden;
              return IconButton(
                tooltip: hidden ? 'Mostrar bibliotecas privadas' : 'Ocultar bibliotecas privadas',
                onPressed: () {
                  state.setPrivateHidden(!hidden);
                  showToast(
                    context,
                    hidden ? 'Bibliotecas privadas visibles' : 'Bibliotecas privadas ocultas',
                    icon: hidden ? Icons.lock_open_rounded : Icons.lock_rounded,
                  );
                },
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Icon(
                    hidden ? Icons.lock_rounded : Icons.lock_open_rounded,
                    key: ValueKey(hidden),
                    color: hidden ? Kofu.accent : null,
                  ),
                ),
              );
            },
          ),
        if (AppScope.of(context).sync.configured && !isDesktop)
          IconButton(
            tooltip: 'Modo mando',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RemoteScreen())),
            icon: const Icon(Icons.settings_remote_rounded),
          ),
        IconButton(
          tooltip: 'Buscar',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(tooltip: 'Ajustes', onPressed: _openSources, icon: const Icon(Icons.settings_rounded)),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _sectionTitle(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
    ),
  );

  /// Las piezas (slivers) de una sección del inicio.
  List<Widget> _section(HomeSection section, AppState state, List<SourceLibraries>? groups) {
    switch (section) {
      case HomeSection.continueReading:
        return [_progressRow(upNext: false)];
      case HomeSection.upNext:
        return [_progressRow(upNext: true)];
      case HomeSection.shortcuts:
        return [_shortcuts()];
      case HomeSection.libraries:
        return [
          _sectionTitle('Bibliotecas'),
          if (groups == null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            _librariesGrid(groups),
        ];
      case HomeSection.complete:
        return [_completeSection(state)];
      case HomeSection.lists:
        return [_sectionTitle('Listas'), _listsGrid(state, groups == null ? const [] : _visibleLibraries(groups))];
    }
  }

  /// "Seguir leyendo" (capítulos a medias) o "Te toca" (siguiente sin empezar),
  /// con cómics y novelas juntos, del más reciente al más antiguo.
  Widget _progressRow({required bool upNext}) {
    return SliverToBoxAdapter(
      child: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          (upNext ? _upNext : _continue) ?? Future.value(const <SourcedBook>[]),
          _novelProgress ?? Future.value((reading: <NovelProgress>[], upNext: <NovelProgress>[])),
        ]),
        builder: (context, snap) {
          final state = AppScope.of(context);
          if (!snap.hasData) return const SizedBox.shrink();
          final books = (snap.data![0] as List<SourcedBook>)
              .where((b) => !state.isLibraryHidden(b.source.id, b.book.libraryId))
              .toList();
          final novelsAll = snap.data![1] as ({List<NovelProgress> reading, List<NovelProgress> upNext});
          final novels = upNext ? novelsAll.upNext : novelsAll.reading;
          // Se mezclan por fecha de lectura ("Te toca" de cómics no trae fecha: van primero los de Komga).
          final items = <(DateTime, Widget)>[
            for (final (i, b) in books.indexed)
              (
                upNext ? DateTime(9999).subtract(Duration(minutes: i)) : (b.book.readDate ?? DateTime(2000)),
                _ComicProgressCard(
                  item: b,
                  upNext: upNext,
                  onTap: () async {
                    await openBook(context, b.source, b.book.id, seriesId: b.book.seriesId);
                    _refreshContinue();
                  },
                  onMarkRead: () async {
                    try {
                      await state.client(b.source.id).setBookRead(b.book.id, true);
                      state.downloads.discardPendingProgress(b.source.id, b.book.id);
                      if (context.mounted) showToast(context, 'Marcado como leído', icon: Icons.done_all_rounded);
                    } catch (e) {
                      if (context.mounted) showToast(context, '$e', icon: Icons.error_outline);
                    }
                    _refreshContinue();
                  },
                ),
              ),
            for (final n in novels)
              (
                n.at,
                _ProgressCard.novel(
                  item: n,
                  upNext: upNext,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NovelReaderScreen(work: n.work, chapters: n.chapters, initialIndex: n.index),
                      ),
                    );
                    _refreshContinue();
                  },
                  onMarkRead: () {
                    state.novels.setRead(n.work, n.chapter, true);
                    showToast(context, 'Marcado como leído', icon: Icons.done_all_rounded);
                    _refreshContinue();
                  },
                ),
              ),
          ]..sort((a, b) => b.$1.compareTo(a.$1));
          if (items.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Row(
                  children: [
                    if (upNext) ...[const Icon(Icons.next_plan_rounded, color: Kofu.accent2), const SizedBox(width: 8)],
                    Expanded(
                      child: Text(
                        upNext ? 'Te toca' : 'Seguir leyendo',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 158,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => items[i].$2,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Fila compacta de accesos: así el inicio no se llena de tarjetas.
  Widget _shortcuts() {
    Future<void> go(Widget screen) async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      _refreshContinue();
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: SizedBox(
          height: 86,
          child: FutureBuilder<int>(
            future: _newsCount,
            builder: (context, snap) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _Shortcut(
                  icon: Icons.fiber_new_rounded,
                  label: 'Novedades',
                  color: const Color(0xFF34D399),
                  badge: (snap.data ?? 0) > 0 ? '${snap.data}' : null,
                  onTap: () async {
                    await go(const NewsScreen());
                    if (mounted) setState(() => _newsCount = Future.value(0));
                  },
                ),
                _Shortcut(
                  icon: Icons.history_rounded,
                  label: 'Historial',
                  color: const Color(0xFF38BDF8),
                  onTap: _openHistory,
                ),
                _Shortcut(
                  icon: Icons.emoji_events_rounded,
                  label: 'Top 10',
                  color: Kofu.gold,
                  onTap: () => go(const Top10Screen()),
                ),
                _Shortcut(
                  icon: Icons.bookmark_rounded,
                  label: 'Marcadores',
                  color: Kofu.accent,
                  onTap: () => go(const BookmarksScreen()),
                ),
                _Shortcut(
                  icon: Icons.sell_rounded,
                  label: 'Etiquetas',
                  color: Kofu.accent2,
                  onTap: () => go(const TagsScreen()),
                ),
                _Shortcut(
                  icon: Icons.download_for_offline_rounded,
                  label: 'Descargas',
                  color: Kofu.read,
                  onTap: () => go(const DownloadsScreen()),
                ),
                _Shortcut(
                  icon: Icons.insights_rounded,
                  label: 'Estadísticas',
                  color: const Color(0xFFF97316),
                  onTap: () => go(const StatsScreen()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _librariesGrid(List<SourceLibraries> groups) {
    final state = AppScope.read(context);
    final offline = groups.where((g) => g.error != null).toList();
    final entries = _visibleLibraries(groups);
    final novelLibs = _novelLibList.where((l) => !state.isLibraryHidden(novelsSourceId, l.id)).toList();
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverMainAxisGroup(
        slivers: [
          for (final g in offline)
            SliverToBoxAdapter(
              child: _OfflineCard(
                group: g,
                onRetry: g.needsSecret
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SourceEditScreen(existing: g.source)),
                      )
                    : _reload,
              ),
            ),
          SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 460,
              childAspectRatio: 2.3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: entries.length + (novelLibs.isEmpty ? 0 : 1),
            itemBuilder: (context, i) {
              // La última tarjeta es "Novelas" (todas las carpetas de novelas juntas).
              if (i == entries.length) {
                return _NovelLibraryCard(
                  libraries: novelLibs,
                  preview: _novelPreview ??= Future.wait(
                    novelLibs.map((l) => state.novels.works(l.id).catchError((_) => <NovelWork>[])),
                  ).then((all) => all.expand((w) => w).toList()),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => NovelLibraryScreen(libraries: novelLibs)),
                  ),
                );
              }
              final e = entries[i];
              final key = 'lib:${e.key}';
              return _LibraryCard(
                entry: e,
                color: state.sourceColor(e.source.id),
                preview: _preview(e),
                modeLabel: state.libraryMode(e.source.id, e.library).label,
                selected: _selection.contains(key),
                onTap: _selection.active
                    ? () => _selection.toggle(key, _LibraryPick(e))
                    : () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryScreen(entry: e)));
                        _refreshContinue();
                      },
                onLongPress: () => _selection.toggle(key, _LibraryPick(e)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _listsGrid(AppState state, List<LibraryEntry> libraries) {
    final data = state.data;
    final lists = data.customLists;
    // Un Favoritos por biblioteca visible, antes que las listas propias.
    final favCount = libraries.length;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          childAspectRatio: 1.55,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: 1 + favCount + lists.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CompleteCard(count: state.visibleItemsOf(UserData.completeId).length, onTap: _openComplete);
          }
          index -= 1;
          if (index < favCount) {
            final e = libraries[index];
            final key = 'fav:${e.key}';
            return _ListCard(
              title: 'Favoritos',
              favorite: true,
              caption: '${e.library.name} · ${e.source.name}',
              tint: state.sourceColor(e.source.id),
              items: state.favoritesOf(e.source.id, e.library.id),
              selected: _selection.contains(key),
              onTap: _selection.active
                  ? () => _selection.toggle(key, _FavPick(e))
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ListScreen(
                            listId: UserData.favoritesId,
                            library: (sourceId: e.source.id, libraryId: e.library.id, name: e.library.name),
                          ),
                        ),
                      );
                      _refreshContinue();
                    },
              onLongPress: () => _selection.toggle(key, _FavPick(e)),
            );
          }
          final i = index - favCount;
          if (i == lists.length) {
            return _NewListCard(
              onTap: () async {
                final name = await askListName(context);
                if (name != null) data.createList(name);
              },
            );
          }
          final list = lists[i];
          final key = 'list:${list.id}';
          return _ListCard(
            title: list.name,
            items: state.visibleItemsOf(list.id),
            selected: _selection.contains(key),
            onTap: _selection.active
                ? () => _selection.toggle(key, _ListPick(list))
                : () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ListScreen(listId: list.id)));
                    _refreshContinue();
                  },
            onLongPress: () => _selection.toggle(key, _ListPick(list)),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Welcome extends StatelessWidget {
  final VoidCallback onAdd;

  const _Welcome({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.1,
            colors: [Color(0x553A1F5C), Kofu.background],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (r) => Kofu.accentGradient.createShader(r),
                child: const Icon(Icons.auto_stories_rounded, size: 88, color: Colors.white),
              ),
              const SizedBox(height: 16),
              const Text('KofuReader', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Conecta tu servidor Komga para empezar', style: TextStyle(color: Kofu.muted)),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Añadir servidor'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncEditScreen())),
                icon: const Icon(Icons.cloud_sync_rounded),
                label: const Text('Ya uso KofuReader en otro dispositivo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acceso de la fila de atajos.
class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _Shortcut({required this.icon, required this.label, required this.color, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Material(
        color: Kofu.surface,
        borderRadius: BorderRadius.circular(Kofu.radius + 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(Kofu.radius + 2),
          onTap: onTap,
          child: SizedBox(
            width: 92,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
                        child: Icon(icon, color: color, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: 6,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        badge!,
                        style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de "Seguir leyendo" / "Te toca", para un capítulo de cómic o de novela.
class _ProgressCard extends StatelessWidget {
  final ImageProvider? image;
  final Widget? fallback;
  final String series;
  final String chapter;
  final String libraryLabel;
  final Color libraryColor;
  final String status;
  final double progress;
  final bool upNext;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  const _ProgressCard({
    required this.image,
    required this.series,
    required this.chapter,
    required this.libraryLabel,
    required this.libraryColor,
    required this.status,
    required this.progress,
    required this.upNext,
    required this.onTap,
    required this.onMarkRead,
    this.fallback,
  });

  factory _ProgressCard.novel({
    required NovelProgress item,
    required bool upNext,
    required VoidCallback onTap,
    required VoidCallback onMarkRead,
  }) => _ProgressCard(
    image: null,
    fallback: _NovelThumb(work: item.work),
    series: item.work.title,
    chapter: item.chapter.label,
    libraryLabel: item.work.lib,
    libraryColor: Kofu.accent2,
    status: upNext
        ? 'Capítulo ${item.index + 1} de ${item.chapters.length}'
        : '${(item.fraction * 100).round()} % leído',
    progress: upNext ? 0 : item.fraction,
    upNext: upNext,
    onTap: onTap,
    onMarkRead: onMarkRead,
  );

  @override
  Widget build(BuildContext context) {
    final cover = image != null ? KomgaImage.provider(image!) : (fallback ?? const SizedBox());
    return SizedBox(
      width: 330,
      child: Material(
        color: Kofu.surface,
        borderRadius: BorderRadius.circular(Kofu.radius + 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              if (image != null) Positioned.fill(child: Opacity(opacity: 0.16, child: cover)),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0x0015151D), Kofu.surface], stops: [0, 0.5]),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(width: 88, child: cover),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Etiqueta de la biblioteca de origen.
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: libraryColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              libraryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: libraryColor, fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            series,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            chapter,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Kofu.muted, fontSize: 12),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Icon(
                                upNext ? Icons.skip_next_rounded : Icons.play_circle_fill_rounded,
                                color: upNext ? Kofu.accent2 : Kofu.accent,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          if (progress > 0) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: Kofu.surfaceHigh,
                                color: Kofu.accent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Marcar como leído sin abrirlo.
                  IconButton(
                    tooltip: 'Marcar como leído',
                    onPressed: onMarkRead,
                    icon: const Icon(Icons.done_all_rounded, color: Kofu.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [_ProgressCard] de un capítulo de cómic: portada, biblioteca y progreso de Komga.
class _ComicProgressCard extends StatelessWidget {
  final SourcedBook item;
  final bool upNext;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  const _ComicProgressCard({required this.item, required this.upNext, required this.onTap, required this.onMarkRead});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final client = state.client(item.source.id);
    final b = item.book;
    final lib = state.libraryName(item.source.id, b.libraryId);
    return _ProgressCard(
      image: CachedCoverImage(client.bookThumbnailUrl(b.id), headers: client.authHeaders),
      series: b.seriesTitle,
      chapter: b.title,
      libraryLabel: lib == null ? item.source.name : '$lib · ${item.source.name}',
      libraryColor: state.sourceColor(item.source.id),
      status: upNext ? '${b.pagesCount} páginas' : 'Pág. ${b.readProgress?.page ?? 0} de ${b.pagesCount}',
      progress: upNext ? 0 : b.progressFraction,
      upNext: upNext,
      onTap: onTap,
      onMarkRead: onMarkRead,
    );
  }
}

class _NovelThumb extends StatelessWidget {
  final NovelWork work;

  const _NovelThumb({required this.work});

  @override
  Widget build(BuildContext context) => novelCover(context, work);
}

/// Tarjeta ancha de biblioteca con un collage de portadas recientes.
class _LibraryCard extends StatelessWidget {
  final LibraryEntry entry;
  final Color color;
  final Future<List<KomgaSeries>> preview;
  final String modeLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LibraryCard({
    required this.entry,
    required this.color,
    required this.preview,
    required this.modeLabel,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final client = AppScope.read(context).client(entry.source.id);
    return _SelectableFrame(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Kofu.surface),
          // Collage a la derecha, inclinado.
          Positioned(
            right: -30,
            top: -20,
            bottom: -20,
            width: 300,
            child: Transform.rotate(
              angle: -0.12,
              child: FutureBuilder<List<KomgaSeries>>(
                future: preview,
                builder: (context, snap) => Row(
                  children: [
                    for (final s in (snap.data ?? const <KomgaSeries>[]).take(3))
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: KomgaImage(url: client.seriesThumbnailUrl(s.id), headers: client.authHeaders),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Kofu.surface, Kofu.surface.withValues(alpha: 0.92), Kofu.surface.withValues(alpha: 0.1)],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
          // Brillo del color del servidor.
          Positioned(
            left: -60,
            top: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [color.withValues(alpha: 0.25), Colors.transparent]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SourceChip(label: entry.source.name, color: color),
                const Spacer(),
                Text(
                  entry.library.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                const SizedBox(height: 2),
                Text(modeLabel, style: const TextStyle(color: Kofu.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de biblioteca de novelas: portadas inclinadas y etiqueta "Novelas".
class _NovelLibraryCard extends StatelessWidget {
  final List<NovelLibrary> libraries;
  final Future<List<NovelWork>> preview;
  final VoidCallback onTap;

  const _NovelLibraryCard({required this.libraries, required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Kofu.radius + 4);
    return Material(
      color: Kofu.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -30,
              top: -20,
              bottom: -20,
              width: 300,
              child: Transform.rotate(
                angle: -0.12,
                child: FutureBuilder<List<NovelWork>>(
                  future: preview,
                  builder: (context, snap) => Row(
                    children: [
                      for (final w in (snap.data ?? const <NovelWork>[]).where((w) => w.hasCover).take(3))
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: novelCover(context, w)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Kofu.surface, Kofu.surface.withValues(alpha: 0.92), Kofu.surface.withValues(alpha: 0.1)],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SourceChip(label: 'Texto', color: Kofu.accent2),
                  const Spacer(),
                  Text(
                    'Novelas',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(' obra · Lectura de texto', style: const TextStyle(color: Kofu.muted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  final String title;
  final bool favorite;
  final String? caption; // p. ej. la biblioteca de un Favoritos
  final Color? tint;
  final List<ListItem> items;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ListCard({
    required this.title,
    required this.items,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.favorite = false,
    this.caption,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final covers = items.where((i) => state.source(i.item.ref.sourceId) != null).take(3).toList();
    return _SelectableFrame(
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (favorite)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Kofu.accent, Color.lerp(Kofu.accent2, tint ?? Kofu.accent2, 0.35)!],
                ),
              ),
            )
          else
            const ColoredBox(color: Kofu.surface),
          // Portadas apiladas a la derecha.
          for (var i = covers.length - 1; i >= 0; i--)
            Positioned(
              right: 14 + i * 26.0,
              top: 14 + i * 6.0,
              bottom: 14 + i * 6.0,
              child: AspectRatio(
                aspectRatio: 0.68,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(-4, 2))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: KomgaImage(
                      url: state.client(covers[i].item.ref.sourceId).thumbnailUrl(covers[i].item.ref),
                      headers: state.client(covers[i].item.ref.sourceId).authHeaders,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  favorite ? Icons.favorite_rounded : Icons.collections_bookmark_rounded,
                  color: favorite ? Colors.white : Kofu.accent,
                ),
                const Spacer(),
                if (caption != null)
                  SizedBox(
                    width: 150,
                    child: Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: favorite ? Colors.white : Kofu.muted,
                      ),
                    ),
                  ),
                SizedBox(
                  width: 150,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${items.length} elemento${items.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: favorite ? Colors.white70 : Kofu.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso mientras se elige qué leer en la tele: el próximo libro que se abra irá a ella.
class _CastBanner extends StatelessWidget {
  const _CastBanner();

  @override
  Widget build(BuildContext context) {
    final hub = AppScope.of(context).remote;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Kofu.accent.withValues(alpha: 0.25), Kofu.accent2.withValues(alpha: 0.25)]),
        borderRadius: BorderRadius.circular(Kofu.radius + 4),
        border: Border.all(color: Kofu.accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tv_rounded, color: Kofu.accent),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Elige qué leer en la tele', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  'Entra en una serie y toca un capítulo (o "Leer"): se abrirá en la tele',
                  style: TextStyle(fontSize: 12, color: Kofu.muted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: hub.cancelChoosing, child: const Text('Cancelar')),
        ],
      ),
    );
  }
}

/// Tarjeta dorada de Ediciones completas en Listas.
class _CompleteCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _CompleteCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Kofu.radius + 4);
    return Material(
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(gradient: Kofu.goldGradient),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                right: -16,
                bottom: -16,
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: 120,
                  color: const Color(0xFF3A2A00).withValues(alpha: 0.12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: Color(0xFF3A2A00)),
                    const Spacer(),
                    const Text(
                      'Ediciones completas',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF3A2A00)),
                    ),
                    const SizedBox(height: 2),
                    Text(' obra', style: const TextStyle(fontSize: 12, color: Color(0xAA3A2A00))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewListCard extends StatelessWidget {
  final VoidCallback onTap;

  const _NewListCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Kofu.radius + 4),
        side: const BorderSide(color: Kofu.outline, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Kofu.radius + 4),
        onTap: onTap,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 32, color: Kofu.muted),
              SizedBox(height: 6),
              Text(
                'Nueva lista',
                style: TextStyle(color: Kofu.muted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineCard extends StatelessWidget {
  final SourceLibraries group;
  final VoidCallback onRetry;

  const _OfflineCard({required this.group, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Kofu.surface,
        borderRadius: BorderRadius.circular(Kofu.radius + 4),
        border: Border.all(color: Kofu.outline),
      ),
      child: Row(
        children: [
          Icon(
            group.needsSecret ? Icons.key_rounded : Icons.cloud_off_rounded,
            color: group.needsSecret ? Kofu.accent : Kofu.muted,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.needsSecret ? group.source.name : '${group.source.name} sin conexión',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  group.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Kofu.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          group.needsSecret
              ? FilledButton(onPressed: onRetry, child: const Text('Añadir'))
              : IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
    );
  }
}

/// Marco redondeado con estado seleccionado para tarjetas grandes.
class _SelectableFrame extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget child;

  const _SelectableFrame({required this.selected, required this.onTap, required this.onLongPress, required this.child});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Kofu.radius + 4);
    return AnimatedScale(
      scale: selected ? 0.96 : 1,
      duration: const Duration(milliseconds: 160),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: selected ? Kofu.accent : Colors.white.withValues(alpha: 0.06),
            width: selected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected ? Kofu.accent.withValues(alpha: 0.3) : Colors.black54,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, onLongPress: onLongPress),
              ),
              if (selected)
                const Positioned(
                  top: 12,
                  right: 12,
                  child: Icon(Icons.check_circle_rounded, color: Kofu.accent, size: 26),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

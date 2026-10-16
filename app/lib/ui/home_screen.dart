import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/user_data.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import 'list_screen.dart';
import 'navigation.dart';
import 'sources_screen.dart';
import 'widgets/cover_card.dart';
import 'widgets/list_sheets.dart';
import 'widgets/selection.dart';

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
  }

  Future<void> _reload() async {
    await AppScope.read(context).sync.syncNow();
    if (!mounted) return;
    setState(() => _load(refresh: true));
    await Future.wait([_libraries!, _continue!]);
  }

  void _refreshContinue() {
    if (mounted) setState(() => _continue = AppScope.read(context).continueReading());
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
                  _continueSection(),
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
                  _sectionTitle('Listas'),
                  _listsGrid(state, groups == null ? const [] : _visibleLibraries(groups)),
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

  Widget _continueSection() {
    return SliverToBoxAdapter(
      child: FutureBuilder<List<SourcedBook>>(
        future: _continue,
        builder: (context, snap) {
          final state = AppScope.of(context);
          final books = snap.data?.where((b) => !state.isLibraryHidden(b.source.id, b.book.libraryId)).toList();
          if (books == null || books.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Text(
                  'Seguir leyendo',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: books.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => _ContinueCard(
                    item: books[i],
                    onTap: () async {
                      await openBook(context, books[i].source, books[i].book.id, seriesId: books[i].book.seriesId);
                      _refreshContinue();
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _librariesGrid(List<SourceLibraries> groups) {
    final state = AppScope.read(context);
    final offline = groups.where((g) => g.error != null).toList();
    final entries = _visibleLibraries(groups);
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
            itemCount: entries.length,
            itemBuilder: (context, i) {
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
        itemCount: favCount + lists.length + 2,
        itemBuilder: (context, index) {
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
            return _DownloadsCard(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsScreen()));
                _refreshContinue();
              },
            );
          }
          if (i == lists.length + 1) {
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

class _ContinueCard extends StatelessWidget {
  final SourcedBook item;
  final VoidCallback onTap;

  const _ContinueCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final client = AppScope.read(context).client(item.source.id);
    final b = item.book;
    final page = b.readProgress?.page ?? 0;
    return SizedBox(
      width: 320,
      child: Material(
        color: Kofu.surface,
        borderRadius: BorderRadius.circular(Kofu.radius + 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // Fondo: la propia portada muy difuminada por el degradado.
              Positioned.fill(
                child: Opacity(
                  opacity: 0.18,
                  child: KomgaImage(url: client.bookThumbnailUrl(b.id), headers: client.authHeaders),
                ),
              ),
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
                      child: SizedBox(
                        width: 88,
                        child: KomgaImage(url: client.bookThumbnailUrl(b.id), headers: client.authHeaders),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.seriesTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Kofu.muted, fontSize: 13),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(Icons.play_circle_fill_rounded, color: Kofu.accent, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'Pág. $page de ${b.pagesCount}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: b.progressFraction,
                              minHeight: 5,
                              backgroundColor: Kofu.surfaceHigh,
                              color: Kofu.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _DownloadsCard extends StatelessWidget {
  final VoidCallback onTap;

  const _DownloadsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final downloads = state.downloads;
    final visible = downloads.all.where((b) => !state.isLibraryHidden(b.sourceId, b.libraryId)).toList();
    final count = visible.length;
    final bytes = visible.fold(0, (a, b) => a + b.sizeBytes);
    final queued = downloads.queuedCount;
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
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(Icons.download_for_offline_rounded, size: 120, color: Kofu.read.withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  queued > 0
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Kofu.read),
                        )
                      : const Icon(Icons.download_done_rounded, color: Kofu.read),
                  const Spacer(),
                  const Text('Descargas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    queued > 0
                        ? '$count libros · $queued en cola'
                        : count == 0
                        ? 'Para leer sin conexión'
                        : '$count libro${count == 1 ? '' : 's'} · ${formatBytes(bytes)}',
                    style: const TextStyle(fontSize: 12, color: Kofu.muted),
                  ),
                ],
              ),
            ),
          ],
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

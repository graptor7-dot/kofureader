import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/chapter_groups.dart';
import '../data/snapshots.dart';
import '../data/source.dart';
import '../komga/chapter_kind.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'navigation.dart' show startReading;
import 'extras_screens.dart';
import 'widgets/cover_card.dart';
import 'widgets/list_sheets.dart';
import 'widgets/reading_mode_picker.dart';
import 'widgets/selection.dart';

/// Ficha de una serie y sus libros.
class SeriesScreen extends StatefulWidget {
  final Source source;
  final String seriesId;
  final KomgaSeries? initial;

  /// Si no es nulo, se muestra solo esa agrupación de la serie (como si fuera otra serie).
  final String? groupId;

  const SeriesScreen({super.key, required this.source, required this.seriesId, this.initial, this.groupId});

  // Fichas abiertas, para que el lector pueda volver a la que ya hay en vez de abrir otra.
  static final _openRoutes = <String, Route<dynamic>>{};

  /// Abre la ficha de la serie desde el lector: vuelve a ella si ya está abierta debajo;
  /// si no (p. ej. se empezó desde Seguir leyendo), sustituye el lector por la ficha.
  static void showFromReader(BuildContext context, Source source, String seriesId) {
    final route = _openRoutes['${source.id}|$seriesId'];
    if (route != null && route.isActive) {
      Navigator.popUntil(context, (r) => r == route || r.isFirst);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SeriesScreen(source: source, seriesId: seriesId),
        ),
      );
    }
  }

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

  String get _routeKey => '${widget.source.id}|${widget.seriesId}${widget.groupId == null ? '' : '|${widget.groupId}'}';
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route != null) SeriesScreen._openRoutes[_routeKey] = _route!;
  }

  @override
  void dispose() {
    if (SeriesScreen._openRoutes[_routeKey] == _route) SeriesScreen._openRoutes.remove(_routeKey);
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
        _classify();
      });
    } catch (e) {
      if (!mounted) return;
      // Sin conexión: mostrar lo descargado de esta serie, si hay.
      final downloads = AppScope.read(context).downloads;
      final local = downloads.ofSeries(_sourceId, widget.seriesId);
      setState(() {
        if (local.isNotEmpty) {
          _books = [for (final b in local) b.toKomgaBook(progress: _localProgress(b.bookId))];
          _offline = true;
          _classify();
          _error = null;
        } else {
          _error = e.toString();
        }
      });
    }
  }

  /// True si la serie se muestra desde las descargas porque no hay conexión.
  bool _offline = false;

  KomgaReadProgress? _localProgress(String bookId) {
    final p = AppScope.read(context).downloads.pendingProgress(_sourceId, bookId);
    return p == null ? null : KomgaReadProgress(p.page, p.completed, null);
  }

  IconData _downloadIcon(AppState state, List<KomgaBook>? books) {
    if (books == null || books.isEmpty) return Icons.download_rounded;
    if (books.any((b) => state.downloads.progressOf(_sourceId, b.id) != null)) return Icons.downloading_rounded;
    if (books.every((b) => state.downloads.isDownloaded(_sourceId, b.id))) return Icons.download_done_rounded;
    return Icons.download_rounded;
  }

  void _enqueue(Iterable<KomgaBook> books) {
    final state = AppScope.read(context);
    final pending = books.where((b) => !state.downloads.isDownloaded(_sourceId, b.id)).toList();
    if (pending.isEmpty) {
      showToast(context, 'Ya está todo descargado', icon: Icons.download_done_rounded);
      return;
    }
    final series = _series;
    state.downloads.enqueue(
      state.client(_sourceId),
      pending,
      libraryName: series == null ? null : state.libraryName(_sourceId, series.libraryId),
    );
    showToast(
      context,
      'Descargando ${pending.length} libro${pending.length == 1 ? '' : 's'}',
      icon: Icons.download_rounded,
    );
  }

  Future<void> _downloadSheet() async {
    final books = _scope;
    if (books == null) return;
    final downloads = AppScope.read(context).downloads;
    final local = downloads
        .ofSeries(_sourceId, widget.seriesId)
        .where((d) => books.any((b) => b.id == d.bookId))
        .toList();
    final unread = books.where((b) => !b.isRead).toList();
    final queued = books.where((b) => downloads.progressOf(_sourceId, b.id) != null).toList();
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text('Descargar todos (${books.length})'),
              onTap: () {
                Navigator.pop(ctx);
                _enqueue(books);
              },
            ),
            if (unread.isNotEmpty && unread.length != books.length)
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: Text('Descargar sin leer (${unread.length})'),
                onTap: () {
                  Navigator.pop(ctx);
                  _enqueue(unread);
                },
              ),
            if (queued.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: Text('Cancelar descargas en curso (${queued.length})'),
                onTap: () {
                  Navigator.pop(ctx);
                  for (final b in queued) {
                    downloads.cancel(_sourceId, b.id);
                  }
                },
              ),
            if (local.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Kofu.accent),
                title: Text(
                  '${widget.groupId == null ? 'Borrar descargas de esta serie' : 'Borrar descargas de la agrupación'} (${local.length})',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  for (final b in local) {
                    await downloads.delete(b.sourceId, b.bookId);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  String? _tag;
  bool _showExtras = false; // apartado Extras en vez de los capítulos

  /// Separa extras y capítulos (reglas de chapter_kind.dart + correcciones manuales).
  void _classify() {
    final data = AppScope.read(context).data;
    final books = _books;
    if (books != null) classifyChapters(books, override: (b) => data.pref(chapterKindPrefKey(_sourceId, b.id)));
  }

  /// Corrección manual: 'extra', 'story' o null (automático).
  void _setKind(Iterable<KomgaBook> books, String? kind) {
    final data = AppScope.read(context).data;
    for (final b in books) {
      data.setPref(chapterKindPrefKey(_sourceId, b.id), kind);
    }
    final n = books.length;
    _selection.clear();
    setState(_classify);
    showToast(context, switch (kind) {
      'extra' => '$n movido${n == 1 ? '' : 's'} a Extras',
      'story' => '$n movido${n == 1 ? '' : 's'} a Capítulos',
      _ => 'Clasificación automática',
    }, icon: Icons.auto_awesome_rounded);
  }

  /// Llegada tardía: capítulo nuevo sin leer con número menor que lo ya leído.
  bool _lateArrival(KomgaBook b) {
    final n = b.parsedNumber;
    final created = b.created;
    if (n == null || created == null || b.isRead || b.isExtra) return false;
    if (DateTime.now().difference(created).inDays > 30) return false;
    final readMax = _chapters.where((x) => x.isRead).map((x) => x.parsedNumber ?? 0).fold(0.0, (a, x) => x > a ? x : a);
    return n < readMax;
  }

  ChapterGroups get _groups => ChapterGroups(AppScope.read(context).data, _sourceId, widget.seriesId);

  /// Agrupación que se está viendo (null en la ficha normal de la serie).
  ChapterGroup? get _group => widget.groupId == null ? null : _groups.byId(widget.groupId!);

  /// Libros de esta vista: los de la agrupación, o todos los de la serie.
  List<KomgaBook>? get _scope {
    final books = _books;
    if (books == null || widget.groupId == null) return books;
    final ids = _group?.bookIds.toSet() ?? const <String>{};
    return books.where((b) => ids.contains(b.id)).toList();
  }

  /// Libros sueltos: en la ficha de la serie, los que no están en ninguna agrupación.
  List<KomgaBook> get _loose {
    if (widget.groupId != null) return _scope!;
    final grouped = _groups.byBook;
    return _books!.where((b) => !grouped.containsKey(b.id)).toList();
  }

  /// Capítulos normales (sin extras), en orden de lectura.
  List<KomgaBook> get _chapters => _loose.where((b) => !b.isExtra).toList();
  List<KomgaBook> get _extras => _loose.where((b) => b.isExtra).toList();

  /// Orden de la lista: los últimos arriba (preferencia sincronizada, para todas las series).
  bool get _newestFirst => AppScope.read(context).data.pref('chapter_order') == 'desc';

  void _toggleOrder() {
    final newest = !_newestFirst;
    AppScope.read(context).data.setPref('chapter_order', newest ? 'desc' : null);
    showToast(
      context,
      newest ? 'Los últimos capítulos salen arriba' : 'Los primeros capítulos salen arriba',
      icon: newest ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
    );
  }

  bool _passes(KomgaBook b) {
    final extras = AppScope.read(context).extras;
    return (_status.isEmpty || _status.contains(b.status)) &&
        (_tag == null || extras.tagsOf(b.snapshot(_sourceId).ref).contains(_tag));
  }

  /// Lo que se ve en la cuadrícula: libros sueltos y, en Capítulos, las agrupaciones
  /// (cada una en el sitio de su primer libro).
  List<Object> get _visibleItems {
    final grouped = widget.groupId == null ? _groups.byBook : const <String, ChapterGroup>{};
    final items = <Object>[];
    final shown = <String>{};
    for (final b in _scope!) {
      final g = grouped[b.id];
      if (g != null) {
        if (_showExtras || shown.contains(g.id)) continue;
        if (_membersOf(g).any(_passes)) {
          shown.add(g.id);
          items.add(g);
        }
      } else if (b.isExtra == _showExtras && _passes(b)) {
        items.add(b);
      }
    }
    return _newestFirst ? items.reversed.toList() : items;
  }

  List<KomgaBook> get _visible => _visibleItems.whereType<KomgaBook>().toList();

  List<KomgaBook> _membersOf(ChapterGroup g) {
    final ids = g.bookIds.toSet();
    return _books!.where((b) => ids.contains(b.id)).toList();
  }

  // ---- Agrupaciones ----

  Future<void> _openGroup(ChapterGroup g) async {
    _selection.clear();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeriesScreen(source: widget.source, seriesId: widget.seriesId, initial: _series, groupId: g.id),
      ),
    );
    if (mounted) _load();
  }

  /// Hoja «Agrupar»: nueva agrupación con lo seleccionado, meterlo en una que ya hay o sacarlo.
  Future<void> _groupSelected() async {
    final ids = _selection.values.map((b) => b.id).toList();
    final groups = _groups.all;
    final current = widget.groupId;
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Agrupar ${ids.length} libro${ids.length == 1 ? '' : 's'}',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_rounded, color: Kofu.accent),
                title: const Text('Nueva agrupación…'),
                onTap: () => Navigator.pop(ctx, '+'),
              ),
              if (current != null)
                ListTile(
                  leading: const Icon(Icons.drive_folder_upload_rounded),
                  title: const Text('Sacar de esta agrupación'),
                  onTap: () => Navigator.pop(ctx, '-'),
                ),
              for (final g in groups)
                if (g.id != current)
                  ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(g.name),
                    subtitle: Text('${g.bookIds.length} libro${g.bookIds.length == 1 ? '' : 's'}'),
                    onTap: () => Navigator.pop(ctx, g.id),
                  ),
            ],
          ),
        ),
      ),
    );
    if (r == null || !mounted) return;
    final api = _groups;
    final n = ids.length;
    switch (r) {
      case '+':
        final name = await askListName(context, title: 'Nueva agrupación', hint: 'Nombre de la miniserie');
        if (name == null || !mounted) return;
        api.create(name, ids);
        showToast(context, 'Agrupación «$name» creada', icon: Icons.folder_rounded);
      case '-':
        api.removeBooks(ids);
        showToast(context, 'Sacado${n == 1 ? '' : 's'} de la agrupación', icon: Icons.drive_folder_upload_rounded);
      default:
        api.addTo(r, ids);
        showToast(context, 'Añadido${n == 1 ? '' : 's'} a «${api.byId(r)?.name}»', icon: Icons.folder_rounded);
    }
    _selection.clear();
    setState(() {});
    // Si la agrupación que se veía se ha quedado vacía, desaparece: volver a la serie.
    if (current != null && _group == null) Navigator.pop(context);
  }

  /// Opciones de una agrupación: nombre, portada y deshacerla.
  Future<void> _groupOptions(ChapterGroup g) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.folder_rounded, color: Kofu.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      g.name,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Cambiar nombre'),
              onTap: () => Navigator.pop(ctx, 'name'),
            ),
            ListTile(
              leading: const Icon(Icons.image_rounded),
              title: const Text('Cambiar portada'),
              onTap: () => Navigator.pop(ctx, 'cover'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_rounded, color: Kofu.accent),
              title: const Text('Deshacer agrupación'),
              subtitle: const Text('Los libros vuelven a salir sueltos; no se borra nada'),
              onTap: () => Navigator.pop(ctx, 'dissolve'),
            ),
          ],
        ),
      ),
    );
    if (r == null || !mounted) return;
    switch (r) {
      case 'name':
        final name = await askListName(context, initial: g.name, title: 'Nombre de la agrupación', hint: 'Nombre');
        if (name == null || !mounted) return;
        _groups.update(g.copyWith(name: name));
      case 'cover':
        await _pickGroupCover(g);
      case 'dissolve':
        _groups.dissolve(g.id);
        showToast(context, 'Agrupación «${g.name}» deshecha', icon: Icons.folder_off_rounded);
        if (widget.groupId == g.id) {
          Navigator.pop(context);
          return;
        }
    }
    if (mounted) setState(() {});
  }

  /// Elige qué libro de la agrupación pone la portada.
  Future<void> _pickGroupCover(ChapterGroup g) async {
    final state = AppScope.read(context);
    final client = state.client(_sourceId);
    final members = _membersOf(g);
    final current = g.coverIn(members.map((b) => b.id).toList());
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Elige la portada de «${g.name}»',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  gridDelegate: coverGridDelegate,
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final b = members[i];
                    final cover = state.downloads.isDownloaded(_sourceId, b.id)
                        ? state.downloads.coverFile(_sourceId, b.id)
                        : null;
                    return CoverCard(
                      imageUrl: client.bookThumbnailUrl(b.id),
                      headers: client.authHeaders,
                      image: cover == null ? null : FileImage(cover),
                      title: b.title,
                      selected: b.id == current,
                      badge: b.id == current ? 'Portada' : null,
                      onTap: () => Navigator.pop(ctx, b.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _groups.update(g.copyWith(coverBookId: picked));
    setState(() {});
    showToast(context, 'Portada cambiada', icon: Icons.image_rounded);
  }

  /// Portada de una agrupación: la del libro elegido (o el primero).
  ({String url, ImageProvider? image}) _groupCover(AppState state, ChapterGroup g) {
    final client = state.client(_sourceId);
    final id = g.coverIn(_membersOf(g).map((b) => b.id).toList()) ?? '';
    final file = state.downloads.isDownloaded(_sourceId, id) ? state.downloads.coverFile(_sourceId, id) : null;
    return (url: client.bookThumbnailUrl(id), image: file == null ? null : FileImage(file));
  }

  /// Se lee siguiendo su apartado: de un capítulo se pasa al siguiente capítulo
  /// (saltando los extras), y de un extra al siguiente extra.
  Future<void> _open(KomgaBook book) async {
    // Un libro agrupado (p. ej. al pulsar Continuar en la serie) sigue por su agrupación.
    final group = widget.groupId == null ? _groups.byBook[book.id] : null;
    final pool = group == null ? _loose : _membersOf(group);
    final books = pool.where((b) => b.isExtra == book.isExtra).toList();
    await startReading(context, widget.source, books, books.indexOf(book));
    if (mounted) _load();
  }

  /// Primer libro empezado; si no, el primero sin leer; si no, el primero.
  KomgaBook _continueBook(List<KomgaBook> all) {
    final books = all.where((b) => !b.isExtra).toList();
    if (books.isEmpty) return all.first;
    return books.where((b) => b.inProgress).firstOrNull ?? books.where((b) => !b.isRead).firstOrNull ?? books.first;
  }

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

  /// Marca libros como leídos o no leídos en Komga.
  Future<void> _setRead(List<KomgaBook> books, bool read) async {
    final state = AppScope.read(context);
    final client = state.client(_sourceId);
    _selection.clear();
    try {
      await Future.wait(books.map((b) => client.setBookRead(b.id, read)));
      for (final b in books) {
        state.downloads.discardPendingProgress(_sourceId, b.id);
      }
      if (mounted) {
        showToast(
          context,
          '${books.length} marcado${books.length == 1 ? '' : 's'} como ${read ? 'leído' : 'no leído'}${books.length == 1 ? '' : 's'}',
          icon: read ? Icons.done_all_rounded : Icons.remove_done_rounded,
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '$e', icon: Icons.error_outline);
    }
    await _load();
  }

  /// Marca la serie entera como leída o no leída.
  Future<void> _setSeriesRead(bool read) async {
    final state = AppScope.read(context);
    try {
      await state.client(_sourceId).setSeriesRead(widget.seriesId, read);
      for (final b in _books ?? const <KomgaBook>[]) {
        state.downloads.discardPendingProgress(_sourceId, b.id);
      }
      if (mounted) {
        showToast(
          context,
          read ? 'Serie marcada como leída' : 'Serie marcada como no leída',
          icon: read ? Icons.done_all_rounded : Icons.remove_done_rounded,
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '$e', icon: Icons.error_outline);
    }
    await _load();
  }

  /// Marca (o desmarca, si ya lo estaban todos) los libros seleccionados como edición completa.
  void _toggleCompleteSelected() {
    final data = AppScope.read(context).data;
    final items = _selection.values.map((b) => b.snapshot(_sourceId)).toList();
    final allComplete = items.every((i) => data.isComplete(i.ref));
    data.setComplete(items, !allComplete);
    showToast(
      context,
      allComplete ? ' quitado de Ediciones completas' : ' marcado como edición completa',
      icon: Icons.workspace_premium_rounded,
    );
    _selection.clear();
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
    final books = _scope;
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
                    tooltip: 'Agrupar',
                    onPressed: _groupSelected,
                    icon: const Icon(Icons.create_new_folder_rounded),
                  ),
                  IconButton(
                    tooltip: 'Añadir a Favoritos',
                    onPressed: _favoriteSelected,
                    icon: const Icon(Icons.favorite_border_rounded),
                  ),
                  IconButton(
                    tooltip: 'Edición completa',
                    onPressed: _toggleCompleteSelected,
                    icon: const Icon(Icons.workspace_premium_rounded, color: Kofu.gold),
                  ),
                  IconButton(
                    tooltip: 'Añadir a lista',
                    onPressed: _addSelectedToList,
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                  if (!_offline)
                    IconButton(
                      tooltip: 'Descargar',
                      onPressed: () {
                        _enqueue(_selection.values);
                        _selection.clear();
                      },
                      icon: const Icon(Icons.download_rounded),
                    ),
                  if (!_offline)
                    PopupMenuButton<bool>(
                      tooltip: 'Leído / no leído',
                      icon: const Icon(Icons.done_all_rounded),
                      onSelected: (read) => _setRead(_selection.values, read),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: true, child: Text('Marcar como leídos')),
                        PopupMenuItem(value: false, child: Text('Marcar como no leídos')),
                      ],
                    ),
                  IconButton(
                    tooltip: 'Etiquetas',
                    onPressed: () async {
                      await showTagsSheet(context, _selection.values.map((b) => b.snapshot(_sourceId)).toList());
                      _selection.clear();
                    },
                    icon: const Icon(Icons.sell_rounded),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Extra / capítulo',
                    icon: const Icon(Icons.auto_awesome_rounded),
                    onSelected: (v) => _setKind(_selection.values, v == 'auto' ? null : v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'extra', child: Text('Es un extra')),
                      PopupMenuItem(value: 'story', child: Text('Es historia (a Capítulos)')),
                      PopupMenuItem(value: 'auto', child: Text('Clasificar automáticamente')),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Añadir al Top 10',
                    onPressed: () async {
                      for (final b in _selection.values) {
                        await addToTop10(context, b.snapshot(_sourceId));
                      }
                      _selection.clear();
                    },
                    icon: const Icon(Icons.emoji_events_rounded, color: Kofu.gold),
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
                if (_offline)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Kofu.surface,
                        borderRadius: BorderRadius.circular(Kofu.radius),
                        border: Border.all(color: Kofu.outline),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 18, color: Kofu.muted),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Sin conexión: mostrando solo los libros descargados',
                              style: TextStyle(color: Kofu.muted, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_loose.any((b) => b.isExtra))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: false,
                            icon: const Icon(Icons.menu_book_rounded),
                            label: Text('Capítulos · ${_chapters.length}'),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: Text('Extras · ${_extras.length}'),
                          ),
                        ],
                        selected: {_showExtras},
                        onSelectionChanged: (v) => setState(() {
                          _showExtras = v.first;
                          _selection.clear();
                        }),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: FilterRow(
                    children: [
                      for (final s in ReadStatus.values)
                        FilterChip(
                          label: Text(
                            '${s.label} · ${books.where((b) => b.isExtra == _showExtras && b.status == s).length}',
                          ),
                          selected: _status.contains(s),
                          onSelected: (_) => setState(() => _status.contains(s) ? _status.remove(s) : _status.add(s)),
                        ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: TagFilterRow(selected: _tag, onSelected: (t) => setState(() => _tag = t)),
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
    final visible = _visibleItems;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      sliver: SliverGrid.builder(
        gridDelegate: coverGridDelegate,
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final item = visible[i];
          if (item is ChapterGroup) {
            final members = _membersOf(item);
            final read = members.where((b) => b.isRead).length;
            final cover = _groupCover(state, item);
            return CoverCard(
              imageUrl: cover.url,
              headers: client.authHeaders,
              image: cover.image,
              stacked: true,
              title: item.name,
              subtitle: '${members.length} libro${members.length == 1 ? '' : 's'} · $read leído${read == 1 ? '' : 's'}',
              tag: 'Agrupación',
              tagColor: Kofu.accent,
              kindIcon: Icons.folder_rounded,
              read: members.isNotEmpty && read == members.length,
              progress: members.isEmpty || read == members.length ? 0 : read / members.length,
              selectionActive: _selection.active,
              onTap: _selection.active ? () {} : () => _openGroup(item),
              onLongPress: _selection.active ? null : () => _groupOptions(item),
            );
          }
          final b = item as KomgaBook;
          final downloaded = state.downloads.isDownloaded(_sourceId, b.id);
          final cover = downloaded ? state.downloads.coverFile(_sourceId, b.id) : null;
          return CoverCard(
            imageUrl: client.bookThumbnailUrl(b.id),
            headers: client.authHeaders,
            image: cover == null ? null : FileImage(cover),
            downloaded: downloaded,
            downloadProgress: state.downloads.progressOf(_sourceId, b.id),
            title: b.title,
            subtitle: b.isExtra && b.parsedNumber != null
                ? 'Tras el cap. ${b.parsedNumber!.floor()} · ${b.pagesCount} págs.'
                : b.inProgress
                ? 'Pág. ${b.readProgress!.page} de ${b.pagesCount}'
                : '${b.pagesCount} páginas',
            badge: b.kind == ChapterKind.probableExtra
                ? '¿Extra?'
                : _lateArrival(b)
                ? 'Nuevo · atrás'
                : null,
            read: b.isRead,
            progress: b.inProgress ? b.progressFraction : 0,
            favorite: state.data.isFavorite(b.snapshot(_sourceId).ref),
            complete: state.data.isComplete(b.snapshot(_sourceId).ref),
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
    final books = _scope;
    final group = _group;
    final groupCover = group == null || _books == null ? null : _groupCover(state, group);
    final thumb = groupCover?.url ?? client.seriesThumbnailUrl(widget.seriesId);
    Widget coverImage() => groupCover?.image != null
        ? KomgaImage.provider(groupCover!.image!)
        : KomgaImage(url: thumb, headers: client.authHeaders);
    final title = group == null ? series?.title ?? '' : '${series?.title ?? ''} – ${group.name}';
    final snap = series?.snapshot(_sourceId);
    final favorite = snap != null && state.data.isFavorite(snap.ref);
    final override = state.seriesModeOverride(_sourceId, widget.seriesId);
    final libName = series == null ? null : state.libraryName(_sourceId, series.libraryId);
    final width = MediaQuery.sizeOf(context).width;
    final coverWidth = width < 600 ? 120.0 : 160.0;

    return SliverAppBar(
      pinned: true,
      expandedHeight: coverWidth * 1.45 + kToolbarHeight + 40,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: _newestFirst
              ? 'Últimos arriba (toca para ver los primeros arriba)'
              : 'Primeros arriba (toca para ver los últimos arriba)',
          onPressed: _toggleOrder,
          icon: Icon(_newestFirst ? Icons.south_rounded : Icons.north_rounded),
        ),
        IconButton(
          tooltip: 'Modo de lectura',
          onPressed: _pickMode,
          icon: Icon(Icons.chrome_reader_mode_rounded, color: override != null ? Kofu.accent : null),
        ),
        if (group != null)
          IconButton(
            tooltip: 'Opciones de la agrupación',
            onPressed: () => _groupOptions(group),
            icon: const Icon(Icons.folder_rounded),
          ),
        if (!_offline && group != null)
          PopupMenuButton<bool>(
            tooltip: 'Leído / no leído',
            icon: const Icon(Icons.done_all_rounded),
            onSelected: (read) => _setRead(books ?? const [], read),
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('Marcar agrupación como leída')),
              PopupMenuItem(value: false, child: Text('Marcar agrupación como no leída')),
            ],
          ),
        if (!_offline && group == null)
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (v) {
              final snap = _series?.snapshot(_sourceId);
              switch (v) {
                case 'read':
                  _setSeriesRead(true);
                case 'unread':
                  _setSeriesRead(false);
                case 'rate' when snap != null:
                  showRatingDialog(context, snap);
                case 'tags' when snap != null:
                  showTagsSheet(context, [snap]);
                case 'top' when snap != null:
                  addToTop10(context, snap);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'rate',
                child: ListTile(leading: Icon(Icons.star_rounded), title: Text('Valorar')),
              ),
              PopupMenuItem(
                value: 'tags',
                child: ListTile(leading: Icon(Icons.sell_rounded), title: Text('Etiquetas')),
              ),
              PopupMenuItem(
                value: 'top',
                child: ListTile(leading: Icon(Icons.emoji_events_rounded), title: Text('Añadir al Top 10')),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'read',
                child: ListTile(leading: Icon(Icons.done_all_rounded), title: Text('Marcar serie como leída')),
              ),
              PopupMenuItem(
                value: 'unread',
                child: ListTile(leading: Icon(Icons.remove_done_rounded), title: Text('Marcar serie como no leída')),
              ),
            ],
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
              child: Opacity(opacity: 0.55, child: coverImage()),
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
                      child: ClipRRect(borderRadius: BorderRadius.circular(Kofu.radius), child: coverImage()),
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
                            title,
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
                              books == null
                                  ? '${series.booksCount} libros · ${series.booksReadCount} leídos'
                                  : '${books.where((b) => !b.isExtra).length} capítulos · '
                                        '${books.where((b) => !b.isExtra && b.isRead).length} leídos'
                                        '${books.any((b) => b.isExtra) ? ' · ${books.where((b) => b.isExtra).length} extras' : ''}'
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
                              if (!_offline) ...[
                                const SizedBox(width: 8),
                                _RoundAction(
                                  tooltip: 'Descargas',
                                  icon: _downloadIcon(state, books),
                                  color:
                                      books != null && books.every((b) => state.downloads.isDownloaded(_sourceId, b.id))
                                      ? Kofu.read
                                      : null,
                                  onTap: books == null ? null : _downloadSheet,
                                ),
                              ],
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

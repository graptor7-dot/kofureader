import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/user_data.dart';
import '../theme.dart';
import 'navigation.dart';
import 'widgets/cover_card.dart';
import 'widgets/list_sheets.dart';
import 'widgets/selection.dart';

/// Contenido de una lista propia o de Favoritos.
class ListScreen extends StatefulWidget {
  final String listId;

  const ListScreen({super.key, required this.listId});

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  final _selection = SelectionController<ItemSnapshot>();
  ItemKind? _kind; // null = todo
  String? _sourceFilter;

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

  List<ListItem> _visible(UserData data) => data
      .itemsOf(widget.listId)
      .where((i) => _kind == null || i.item.ref.kind == _kind)
      .where((i) => _sourceFilter == null || i.item.ref.sourceId == _sourceFilter)
      .toList();

  Future<void> _random(List<ListItem> visible) async {
    final pool = _selection.active ? _selection.values : visible.map((i) => i.item).toList();
    if (pool.isEmpty) {
      showToast(context, 'No hay nada para elegir', icon: Icons.info_outline);
      return;
    }
    _selection.clear();
    await openSnapshot(context, pickRandom(pool));
  }

  Future<void> _rename(UserList list) async {
    final name = await askListName(context, initial: list.name, title: 'Renombrar lista');
    if (name != null && mounted) AppScope.read(context).data.renameList(list.id, name);
  }

  Future<void> _delete(UserList list) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar lista?'),
        content: Text('Se borrará "${list.name}". Las series y libros siguen en Komga.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      AppScope.read(context).data.deleteList(list.id);
      Navigator.pop(context);
    }
  }

  void _removeSelected(UserData data) {
    final n = _selection.count;
    data.removeAll(widget.listId, _selection.values.map((s) => s.ref));
    _selection.clear();
    showToast(context, '$n quitado${n == 1 ? '' : 's'} de la lista', icon: Icons.remove_circle_outline);
  }

  Future<void> _addSelectedToList() async {
    await showAddToListSheet(context, _selection.values);
    _selection.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final data = state.data;
    final list = data.list(widget.listId);
    if (list == null) return const Scaffold();
    final all = data.itemsOf(widget.listId);
    final visible = _visible(data);
    final sourceIds = {for (final i in all) i.item.ref.sourceId};

    return PopScope(
      canPop: !_selection.active,
      onPopInvokedWithResult: (didPop, _) => _selection.clear(),
      child: Scaffold(
        floatingActionButton: all.isEmpty
            ? null
            : RandomFab(onPressed: () => _random(visible), selectedCount: _selection.count),
        appBar: _selection.active
            ? SelectionBar(
                count: _selection.count,
                onClose: _selection.clear,
                onSelectAll: () => _selection.selectAll({for (final i in visible) i.item.ref.key: i.item}),
                actions: [
                  IconButton(
                    tooltip: 'Añadir a otra lista',
                    onPressed: _addSelectedToList,
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                  IconButton(
                    tooltip: 'Quitar de esta lista',
                    onPressed: () => _removeSelected(data),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              )
            : null,
        body: CustomScrollView(
          slivers: [
            if (!_selection.active)
              SliverAppBar(
                pinned: true,
                expandedHeight: 190,
                actions: [
                  if (!list.isFavorites)
                    PopupMenuButton<String>(
                      onSelected: (v) => v == 'rename' ? _rename(list) : _delete(list),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                        PopupMenuItem(value: 'delete', child: Text('Borrar lista')),
                      ],
                    ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14, end: 56),
                  title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: list.isFavorites
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Kofu.accent.withValues(alpha: 0.75),
                                    Kofu.accent2.withValues(alpha: 0.35),
                                    Kofu.background,
                                  ],
                                  stops: const [0, 0.55, 1],
                                )
                              : const RadialGradient(
                                  center: Alignment(-1, -1),
                                  radius: 1.6,
                                  colors: [Color(0x448C6BFF), Kofu.background],
                                ),
                        ),
                      ),
                      Positioned(
                        right: 24,
                        bottom: 24,
                        child: Icon(
                          list.isFavorites ? Icons.favorite_rounded : Icons.collections_bookmark_rounded,
                          size: 96,
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: FilterRow(
                children: [
                  ChoiceChip(
                    label: Text('Todo · ${all.length}'),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  ChoiceChip(
                    label: Text('Series · ${all.where((i) => i.item.ref.kind == ItemKind.series).length}'),
                    selected: _kind == ItemKind.series,
                    onSelected: (_) => setState(() => _kind = ItemKind.series),
                  ),
                  ChoiceChip(
                    label: Text('Libros · ${all.where((i) => i.item.ref.kind == ItemKind.book).length}'),
                    selected: _kind == ItemKind.book,
                    onSelected: (_) => setState(() => _kind = ItemKind.book),
                  ),
                  if (sourceIds.length > 1)
                    for (final id in sourceIds)
                      FilterChip(
                        avatar: CircleAvatar(backgroundColor: state.sourceColor(id), radius: 5),
                        label: Text(state.source(id)?.name ?? 'Servidor quitado'),
                        selected: _sourceFilter == id,
                        onSelected: (_) => setState(() => _sourceFilter = _sourceFilter == id ? null : id),
                      ),
                ],
              ),
            ),
            if (all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        list.isFavorites ? Icons.favorite_border_rounded : Icons.collections_bookmark_outlined,
                        size: 56,
                        color: Kofu.muted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        list.isFavorites
                            ? 'Pulsa ♥ en una serie o libro para guardarlo aquí'
                            : 'Mantén pulsada una serie o libro y añádelo a esta lista',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Kofu.muted),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                sliver: SliverGrid.builder(
                  gridDelegate: coverGridDelegate,
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final item = visible[i].item;
                    final source = state.source(item.ref.sourceId);
                    final key = item.ref.key;
                    final isBook = item.ref.kind == ItemKind.book;
                    final client = source == null ? null : state.client(source.id);
                    return CoverCard(
                      imageUrl: client?.thumbnailUrl(item.ref) ?? '',
                      headers: client?.authHeaders ?? const {},
                      title: item.title,
                      subtitle: isBook
                          ? item.seriesTitle
                          : state.libraryName(item.ref.sourceId, item.libraryId) ?? source?.name,
                      sourceColor: state.sourceColor(item.ref.sourceId),
                      kindIcon: isBook ? Icons.menu_book_rounded : null,
                      favorite: !list.isFavorites && data.isFavorite(item.ref),
                      selected: _selection.contains(key),
                      selectionActive: _selection.active,
                      onTap: _selection.active ? () => _selection.toggle(key, item) : () => openSnapshot(context, item),
                      onLongPress: () => _selection.toggle(key, item),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

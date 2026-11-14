import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/cover_cache.dart';
import '../data/extras.dart';
import '../data/user_data.dart';
import '../theme.dart';
import 'navigation.dart';
import 'widgets/cover_card.dart';
import 'widgets/list_sheets.dart' show askListName;
import 'widgets/selection.dart';

// ===========================================================================
// Utilidades comunes
// ===========================================================================

/// Nombre legible de la biblioteca de un elemento ("Manga · Privado").
String libraryLabel(AppState state, String sourceId, String libraryId) {
  final source = state.source(sourceId);
  final lib = state.libraryName(sourceId, libraryId);
  return [?lib, ?source?.name].join(' · ');
}

ImageProvider? itemCover(AppState state, ItemSnapshot item) {
  if (state.source(item.ref.sourceId) == null) return null;
  final client = state.client(item.ref.sourceId);
  return CachedCoverImage(client.thumbnailUrl(item.ref), headers: client.authHeaders);
}

class _Cover extends StatelessWidget {
  final ImageProvider? image;
  const _Cover({required this.image});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: 52,
      height: 74,
      child: image == null
          ? const ColoredBox(color: Kofu.surfaceHigh, child: Icon(Icons.image_not_supported_outlined))
          : KomgaImage.provider(image!),
    ),
  );
}

/// Cabecera grande con degradado de color, común a las pantallas nuevas.
SliverAppBar _header(String title, IconData icon, Color color, {List<Widget> actions = const []}) => SliverAppBar(
  pinned: true,
  expandedHeight: 150,
  actions: actions,
  flexibleSpace: FlexibleSpaceBar(
    titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    background: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1, -1),
              radius: 1.6,
              colors: [color.withValues(alpha: 0.3), Kofu.background],
            ),
          ),
        ),
        Positioned(right: 24, bottom: 20, child: Icon(icon, size: 96, color: Colors.white.withValues(alpha: 0.1))),
      ],
    ),
  ),
);

Widget _empty(IconData icon, String text) => SliverFillRemaining(
  hasScrollBody: false,
  child: Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Kofu.muted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Kofu.muted),
          ),
        ],
      ),
    ),
  ),
);

// ===========================================================================
// Valoración
// ===========================================================================

/// Estrellas de solo lectura (para portadas y listas).
class StarsLabel extends StatelessWidget {
  final int stars;
  final double size;

  const StarsLabel(this.stars, {super.key, this.size = 14});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: Kofu.gold),
    ],
  );
}

Future<void> showRatingDialog(BuildContext context, ItemSnapshot item) async {
  final extras = AppScope.read(context).extras;
  var current = extras.rating(item.ref);
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: Text(item.seriesTitle ?? item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                iconSize: 38,
                onPressed: () => setDialog(() => current = i == current ? 0 : i),
                icon: Icon(i <= current ? Icons.star_rounded : Icons.star_outline_rounded, color: Kofu.gold),
              ),
          ],
        ),
        actions: [
          if (extras.rating(item.ref) > 0)
            TextButton(
              onPressed: () {
                extras.setRating(item, 0);
                Navigator.pop(ctx);
              },
              child: const Text('Quitar'),
            ),
          FilledButton(
            onPressed: () {
              extras.setRating(item, current);
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

// ===========================================================================
// Etiquetas
// ===========================================================================

/// Hoja para poner o quitar etiquetas a uno o varios elementos (y crear nuevas).
Future<void> showTagsSheet(BuildContext context, List<ItemSnapshot> items) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TagsSheet(items: items),
  );
}

class _TagsSheet extends StatelessWidget {
  final List<ItemSnapshot> items;

  const _TagsSheet({required this.items});

  @override
  Widget build(BuildContext context) {
    final extras = AppScope.of(context).extras;
    final tags = extras.tags;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                items.length == 1 ? 'Etiquetas de "${items.first.title}"' : 'Etiquetas de ${items.length} elementos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in tags)
                    Builder(
                      builder: (context) {
                        final count = items.where((i) => extras.tagsOf(i.ref).contains(t.id)).length;
                        final all = count == items.length;
                        return CheckboxListTile(
                          tristate: true,
                          value: all ? true : (count == 0 ? false : null),
                          secondary: CircleAvatar(radius: 8, backgroundColor: t.colorValue),
                          title: Text(t.name),
                          onChanged: (_) => extras.toggleTag(items, t.id, !all),
                        );
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('Nueva etiqueta'),
                    onTap: () async {
                      final name = await askListName(context, title: 'Nueva etiqueta');
                      if (name == null) return;
                      final tag = extras.createTag(name);
                      extras.toggleTag(items, tag.id, true);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Fila de chips de etiquetas para filtrar.
class TagFilterRow extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;

  const TagFilterRow({super.key, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final tags = AppScope.of(context).extras.tags;
    if (tags.isEmpty) return const SizedBox.shrink();
    return FilterRow(
      children: [
        for (final t in tags)
          FilterChip(
            avatar: CircleAvatar(radius: 5, backgroundColor: t.colorValue),
            label: Text(t.name),
            selected: selected == t.id,
            onSelected: (_) => onSelected(selected == t.id ? null : t.id),
          ),
      ],
    );
  }
}

class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  String? _tagId;
  String? _libKey; // sourceId|libraryId

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final extras = state.extras;
    final tags = extras.tags;
    final tag = tags.where((t) => t.id == _tagId).firstOrNull ?? tags.firstOrNull;
    final all = tag == null ? const <ItemSnapshot>[] : extras.tagged(tag.id).where(state.isVisible).toList();
    final libs = {for (final i in all) '${i.ref.sourceId}|${i.libraryId}'};
    final items = all.where((i) => _libKey == null || '${i.ref.sourceId}|${i.libraryId}' == _libKey).toList();
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _header(
            'Etiquetas',
            Icons.sell_rounded,
            Kofu.accent2,
            actions: [
              IconButton(
                tooltip: 'Nueva etiqueta',
                onPressed: () async {
                  final name = await askListName(context, title: 'Nueva etiqueta');
                  if (name != null) setState(() => _tagId = extras.createTag(name).id);
                },
                icon: const Icon(Icons.add_rounded),
              ),
              if (tag != null)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'delete') {
                      extras.deleteTag(tag.id);
                      setState(() => _tagId = null);
                    } else {
                      final name = await askListName(context, initial: tag.name, title: 'Renombrar etiqueta');
                      if (name != null) extras.renameTag(tag.id, name);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renombrar etiqueta')),
                    PopupMenuItem(value: 'delete', child: Text('Borrar etiqueta')),
                  ],
                ),
            ],
          ),
          if (tags.isEmpty)
            _empty(
              Icons.sell_outlined,
              'Crea etiquetas con el botón +\ny pónselas a series o capítulos desde la selección múltiple.',
            )
          else ...[
            SliverToBoxAdapter(
              child: FilterRow(
                children: [
                  for (final t in tags)
                    ChoiceChip(
                      avatar: CircleAvatar(radius: 5, backgroundColor: t.colorValue),
                      label: Text('${t.name} · ${extras.tagged(t.id).length}'),
                      selected: tag?.id == t.id,
                      onSelected: (_) => setState(() {
                        _tagId = t.id;
                        _libKey = null;
                      }),
                    ),
                ],
              ),
            ),
            if (libs.length > 1)
              SliverToBoxAdapter(
                child: FilterRow(
                  children: [
                    for (final k in libs)
                      FilterChip(
                        label: Text(libraryLabel(state, k.split('|').first, k.split('|').last)),
                        selected: _libKey == k,
                        onSelected: (_) => setState(() => _libKey = _libKey == k ? null : k),
                      ),
                  ],
                ),
              ),
            if (items.isEmpty)
              _empty(Icons.sell_outlined, 'Nada con esta etiqueta todavía')
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                sliver: SliverGrid.builder(
                  gridDelegate: coverGridDelegate,
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return CoverCard(
                      imageUrl: '',
                      headers: const {},
                      image: itemCover(state, item),
                      title: item.title,
                      subtitle: item.seriesTitle ?? libraryLabel(state, item.ref.sourceId, item.libraryId),
                      kindIcon: item.ref.kind == ItemKind.book ? Icons.menu_book_rounded : null,
                      sourceColor: state.sourceColor(item.ref.sourceId),
                      onTap: () => openSnapshot(context, item),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Top 10
// ===========================================================================

/// Añade al Top 10 de su biblioteca. Si ya hay 10, pregunta cuál quitar.
Future<void> addToTop10(BuildContext context, ItemSnapshot item) async {
  final state = AppScope.read(context);
  final extras = state.extras;
  final list = extras.top10(item.ref.sourceId, item.libraryId);
  if (list.any((i) => i.ref == item.ref)) {
    showToast(context, 'Ya está en el Top 10', icon: Icons.emoji_events_rounded);
    return;
  }
  if (list.length < Extras.topSize) {
    extras.setTop10(item.ref.sourceId, item.libraryId, [...list, item]);
    showToast(context, 'Añadido al Top 10 (puesto ${list.length + 1})', icon: Icons.emoji_events_rounded);
    return;
  }
  final replace = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('El Top 10 está completo'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Cuál quitas para meter "${item.title}"?', style: const TextStyle(color: Kofu.muted)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, e) in list.indexed)
                    ListTile(
                      dense: true,
                      leading: Text(
                        '${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Kofu.gold),
                      ),
                      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.swap_horiz_rounded),
                      onTap: () => Navigator.pop(ctx, i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
    ),
  );
  if (replace == null) return;
  final updated = [...list]..[replace] = item;
  extras.setTop10(item.ref.sourceId, item.libraryId, updated);
  if (context.mounted) showToast(context, 'Top 10 actualizado', icon: Icons.emoji_events_rounded);
}

class Top10Screen extends StatefulWidget {
  final String? initialLibrary; // sourceId|libraryId

  const Top10Screen({super.key, this.initialLibrary});

  @override
  State<Top10Screen> createState() => _Top10ScreenState();
}

class _Top10ScreenState extends State<Top10Screen> {
  late String? _lib = widget.initialLibrary;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final extras = state.extras;
    final libs = [
      for (final (s, l) in extras.top10Libraries)
        if (!state.isLibraryHidden(s, l)) '$s|$l',
    ];
    final current = libs.contains(_lib) ? _lib : libs.firstOrNull;
    final parts = current?.split('|');
    final items = parts == null ? const <ItemSnapshot>[] : extras.top10(parts[0], parts[1]);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _header('Top 10', Icons.emoji_events_rounded, Kofu.gold),
          if (libs.isEmpty)
            _empty(
              Icons.emoji_events_outlined,
              'Añade obras a tu Top 10 desde la ficha de una serie (menú ⋮)\no con la selección múltiple en una biblioteca.',
            )
          else ...[
            SliverToBoxAdapter(
              child: FilterRow(
                children: [
                  for (final k in libs)
                    ChoiceChip(
                      label: Text(libraryLabel(state, k.split('|').first, k.split('|').last)),
                      selected: current == k,
                      onSelected: (_) => setState(() => _lib = k),
                    ),
                ],
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Mantén pulsado y arrastra para reordenar',
                  style: TextStyle(color: Kofu.muted, fontSize: 12),
                ),
              ),
            ),
            SliverReorderableList(
              itemCount: items.length,
              onReorderItem: (from, to) {
                final list = [...items];
                final moved = list.removeAt(from);
                list.insert(to, moved);
                extras.setTop10(parts![0], parts[1], list);
              },
              itemBuilder: (context, i) {
                final item = items[i];
                final medal = i == 0
                    ? Kofu.gold
                    : i == 1
                    ? const Color(0xFFC0C6D0)
                    : i == 2
                    ? const Color(0xFFCD7F32)
                    : Kofu.muted;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(item.ref.key),
                  index: i,
                  child: Material(
                    color: Kofu.background,
                    child: InkWell(
                      onTap: () => openSnapshot(context, item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: medal),
                              ),
                            ),
                            _Cover(image: itemCover(state, item)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.seriesTitle ?? item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  if (item.seriesTitle != null)
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Kofu.muted, fontSize: 12),
                                    ),
                                  if (extras.rating(item.ref) > 0) ...[
                                    const SizedBox(height: 4),
                                    StarsLabel(extras.rating(item.ref)),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Quitar del Top 10',
                              onPressed: () => extras.setTop10(parts![0], parts[1], [...items]..removeAt(i)),
                              icon: const Icon(Icons.close_rounded, color: Kofu.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Marcadores
// ===========================================================================

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  String? _libKey;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final all = state.extras.bookmarks.where((b) => state.isVisible(b.book)).toList();
    final libs = {for (final b in all) '${b.book.ref.sourceId}|${b.book.libraryId}'}.toList();
    final current = libs.contains(_libKey) ? _libKey : libs.firstOrNull;
    final items = all.where((b) => '${b.book.ref.sourceId}|${b.book.libraryId}' == current).toList();
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _header('Marcadores', Icons.bookmark_rounded, Kofu.accent),
          if (all.isEmpty)
            _empty(Icons.bookmark_outline_rounded, 'En el lector, toca el centro y pulsa 🔖\npara guardar la página.')
          else ...[
            SliverToBoxAdapter(
              child: FilterRow(
                children: [
                  for (final k in libs)
                    ChoiceChip(
                      label: Text(
                        '${libraryLabel(state, k.split('|').first, k.split('|').last)} · '
                        '${all.where((b) => '${b.book.ref.sourceId}|${b.book.libraryId}' == k).length}',
                      ),
                      selected: current == k,
                      onSelected: (_) => setState(() => _libKey = k),
                    ),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final bm = items[i];
                final source = state.source(bm.book.ref.sourceId);
                final client = source == null ? null : state.client(source.id);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: _Cover(
                    image: client == null
                        ? null
                        : CachedCoverImage(
                            client.pageThumbnailUrl(bm.book.ref.komgaId, bm.page),
                            headers: client.authHeaders,
                          ),
                  ),
                  title: Text(bm.book.seriesTitle ?? bm.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${bm.book.title} · pág. ${bm.page}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Kofu.muted),
                  ),
                  trailing: IconButton(
                    tooltip: 'Quitar marcador',
                    onPressed: () => state.extras.setBookmark(bm.book, bm.page, false),
                    icon: const Icon(Icons.bookmark_remove_rounded, color: Kofu.muted),
                  ),
                  onTap: source == null
                      ? null
                      : () => openBook(context, source, bm.book.ref.komgaId, seriesId: bm.book.seriesId, page: bm.page),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Novedades
// ===========================================================================

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  late final AppState _state = AppScope.read(context);
  late final DateTime _seenBefore = _state.newsSeenAt;
  late Future<List<SourcedBook>> _future = _state.news();

  @override
  void initState() {
    super.initState();
    _state.markNewsSeen();
  }

  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  String _day(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    return '${d.day} ${_months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          final f = _state.news();
          setState(() => _future = f);
          await f;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _header('Novedades', Icons.fiber_new_rounded, const Color(0xFF34D399)),
            FutureBuilder<List<SourcedBook>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return _empty(Icons.fiber_new_outlined, 'No hay capítulos nuevos en las series que sigues');
                }
                final rows = <Widget>[];
                String? last;
                for (final b in items) {
                  final created = b.book.created?.toLocal();
                  final day = created == null ? 'Sin fecha' : _day(created);
                  if (day != last) {
                    rows.add(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Text(day, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    );
                    last = day;
                  }
                  final client = state.client(b.source.id);
                  final isNew = created != null && created.isAfter(_seenBefore);
                  rows.add(
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: _Cover(
                        image: CachedCoverImage(client.bookThumbnailUrl(b.book.id), headers: client.authHeaders),
                      ),
                      title: Row(
                        children: [
                          if (isNew)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle),
                            ),
                          Expanded(
                            child: Text(
                              b.book.seriesTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${b.book.title}\n${libraryLabel(state, b.source.id, b.book.libraryId)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Kofu.muted, fontSize: 12),
                      ),
                      onTap: () => openBook(context, b.source, b.book.id, seriesId: b.book.seriesId),
                    ),
                  );
                }
                rows.add(const SizedBox(height: 40));
                return SliverList.list(children: rows);
              },
            ),
          ],
        ),
      ),
    );
  }
}

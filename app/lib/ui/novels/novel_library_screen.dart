import 'package:flutter/material.dart';

import '../../data/app_scope.dart';
import '../../data/cover_cache.dart';
import '../../data/novels.dart';
import '../../theme.dart';
import '../widgets/cover_card.dart';
import '../widgets/selection.dart';
import 'novel_work_screen.dart';

/// Portada de una obra (o un marcador con el título si no tiene).
Widget novelCover(BuildContext context, NovelWork work, {BoxFit fit = BoxFit.cover}) {
  final image = novelCoverImage(AppScope.read(context).novels, work);
  if (image == null) return _NoCover(title: work.title);
  return KomgaImage.provider(image, fit: fit);
}

/// Portada descargada si la hay; si no, la de KofuSync (o null si no tiene).
ImageProvider? novelCoverImage(NovelService novels, NovelWork work) {
  if (!work.hasCover) return null;
  final file = novels.offlineCover(work);
  if (file != null) return FileImage(file);
  return CachedCoverImage(novels.coverUrl(work), headers: novels.headers);
}

class _NoCover extends StatelessWidget {
  final String title;

  const _NoCover({required this.title});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2A2140), Color(0xFF15151D)],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_stories_rounded, color: Kofu.accent2, size: 32),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

/// Etiqueta corta del tipo de novela según su subcarpeta (Novelas Web → Novela web).
(String, Color) novelType(String libraryName) {
  final n = libraryName.toLowerCase();
  if (n.contains('web')) return ('Novela web', const Color(0xFF2DD4BF));
  if (n.contains('liger') || n.contains('light')) return ('Novela ligera', const Color(0xFFF472B6));
  if (n.contains('visual')) return ('Novela visual', const Color(0xFFFBBF24));
  return (libraryName, Kofu.accent2);
}

/// La biblioteca "Novelas": todas las obras, con un filtro por subcarpeta
/// (Novelas Web, Novelas Ligeras…).
class NovelLibraryScreen extends StatefulWidget {
  final List<NovelLibrary> libraries;

  const NovelLibraryScreen({super.key, required this.libraries});

  @override
  State<NovelLibraryScreen> createState() => _NovelLibraryScreenState();
}

class _NovelLibraryScreenState extends State<NovelLibraryScreen> {
  late Future<List<NovelWork>> _future = _load();
  String _search = '';
  String? _lib; // null = todas

  Future<List<NovelWork>> _load() async {
    final novels = AppScope.read(context).novels;
    final perLib = await Future.wait(widget.libraries.map((l) => novels.works(l.id)));
    return perLib.expand((w) => w).toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  void _open(NovelWork w) {
    final lib = widget.libraries.where((l) => l.id == w.lib).firstOrNull;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovelWorkScreen(work: w, libraryName: lib?.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final novels = AppScope.of(context).novels;
    return FutureBuilder<List<NovelWork>>(
      future: _future,
      builder: (context, snap) {
        final all = snap.data ?? const <NovelWork>[];
        final q = _search.toLowerCase();
        final works = all
            .where((w) => _lib == null || w.lib == _lib)
            .where((w) => q.isEmpty || w.title.toLowerCase().contains(q))
            .toList();
        return Scaffold(
          floatingActionButton: works.isEmpty ? null : RandomFab(onPressed: () => _open(pickRandom(works))),
          body: RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 120,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14),
                    title: const Text('Novelas', style: TextStyle(fontWeight: FontWeight.w800)),
                    background: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-1, -1),
                          radius: 1.6,
                          colors: [Color(0x448C6BFF), Kofu.background],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      onChanged: (t) => setState(() => _search = t.trim()),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Buscar obras',
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                if (widget.libraries.length > 1)
                  SliverToBoxAdapter(
                    child: FilterRow(
                      children: [
                        ChoiceChip(
                          label: Text('Todas · ${all.length}'),
                          selected: _lib == null,
                          onSelected: (_) => setState(() => _lib = null),
                        ),
                        for (final l in widget.libraries)
                          ChoiceChip(
                            label: Text('${l.name} · ${all.where((w) => w.lib == l.id).length}'),
                            selected: _lib == l.id,
                            onSelected: (_) => setState(() => _lib = l.id),
                          ),
                      ],
                    ),
                  ),
                if (snap.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${snap.error}', textAlign: TextAlign.center),
                          TextButton(onPressed: _reload, child: const Text('Reintentar')),
                        ],
                      ),
                    ),
                  )
                else if (!snap.hasData)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else if (works.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          all.isEmpty
                              ? 'Aún no hay obras.\nCrea una carpeta por obra en el NAS, con su portada y un .txt por capítulo.'
                              : 'Sin resultados',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Kofu.muted),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    sliver: SliverGrid.builder(
                      gridDelegate: coverGridDelegate,
                      itemCount: works.length,
                      itemBuilder: (context, i) {
                        final w = works[i];
                        final lib = widget.libraries.where((l) => l.id == w.lib).firstOrNull;
                        final type = lib == null ? null : novelType(lib.name);
                        return CoverCard(
                          imageUrl: '',
                          headers: const {},
                          image: novelCoverImage(novels, w),
                          placeholder: w.hasCover ? null : _NoCover(title: w.title),
                          title: w.title,
                          subtitle: '${w.chapters} capítulo${w.chapters == 1 ? '' : 's'}',
                          badge: novels.started(w) ? 'Leyendo' : null,
                          tag: type?.$1,
                          tagColor: type?.$2,
                          downloaded: novels.isDownloaded(w),
                          downloadProgress: novels.downloadProgress(w),
                          onTap: () => _open(w),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../data/app_scope.dart';
import '../../data/novels.dart';
import '../../theme.dart';
import '../widgets/selection.dart';
import 'novel_library_screen.dart' show novelCover;
import 'novel_reader_screen.dart';

/// Ficha de una novela: portada y lista de capítulos (agrupados por volumen si los hay).
class NovelWorkScreen extends StatefulWidget {
  final NovelWork work;

  const NovelWorkScreen({super.key, required this.work});

  @override
  State<NovelWorkScreen> createState() => _NovelWorkScreenState();
}

class _NovelWorkScreenState extends State<NovelWorkScreen> {
  late Future<List<NovelChapter>> _future = _load();

  Future<List<NovelChapter>> _load() => AppScope.read(context).novels.chapters(widget.work);

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  Future<void> _open(List<NovelChapter> chapters, int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovelReaderScreen(work: widget.work, chapters: chapters, initialIndex: index),
      ),
    );
    if (mounted) setState(() {}); // refrescar marcas de leído
  }

  /// Último capítulo abierto; si no, el primero sin leer; si no, el primero.
  int _continueIndex(List<NovelChapter> chapters) {
    final novels = AppScope.read(context).novels;
    final last = novels.lastChapterId(widget.work);
    final i = chapters.indexWhere((c) => c.id == last);
    if (i >= 0) return i;
    final unread = chapters.indexWhere((c) => !novels.isRead(widget.work, c));
    return unread >= 0 ? unread : 0;
  }

  @override
  Widget build(BuildContext context) {
    final novels = AppScope.of(context).novels;
    final work = widget.work;
    return FutureBuilder<List<NovelChapter>>(
      future: _future,
      builder: (context, snap) {
        final chapters = snap.data;
        final readCount = chapters?.where((c) => novels.isRead(work, c)).length ?? 0;
        final rows = <Widget>[];
        if (chapters != null) {
          String? volume;
          for (var i = 0; i < chapters.length; i++) {
            final c = chapters[i];
            if (c.volume != null && c.volume != volume) {
              volume = c.volume;
              rows.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                  child: Text(volume!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              );
            }
            final read = novels.isRead(work, c);
            final pos = novels.position(work, c);
            rows.add(
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: SizedBox(
                  width: 40,
                  child: Text(
                    c.number?.toString() ?? '•',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800, color: read ? Kofu.muted : Kofu.accent),
                  ),
                ),
                title: Text(
                  c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: read ? Kofu.muted : null),
                ),
                trailing: read
                    ? const Icon(Icons.check_circle_rounded, color: Kofu.read, size: 20)
                    : pos != null && pos > 0.02
                    ? Text('${(pos * 100).round()} %', style: const TextStyle(color: Kofu.accent, fontSize: 12))
                    : null,
                onTap: () => _open(chapters, i),
                onLongPress: () {
                  novels.setRead(work, c, !read);
                  setState(() {});
                  showToast(context, read ? 'Marcado como no leído' : 'Marcado como leído');
                },
              ),
            );
          }
        }

        return Scaffold(
          floatingActionButton: chapters == null || chapters.isEmpty
              ? null
              : RandomFab(onPressed: () => _open(chapters, random.nextInt(chapters.length))),
          body: RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 330,
                  title: Text(work.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.parallax,
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                          child: Opacity(opacity: 0.5, child: novelCover(context, work)),
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
                                  width: 140,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(Kofu.radius),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, 10)),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(Kofu.radius),
                                    child: novelCover(context, work),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        work.lib,
                                        style: const TextStyle(color: Kofu.accent2, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        work.title,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${work.chapters} capítulos · $readCount leídos',
                                        style: const TextStyle(color: Kofu.muted, fontSize: 13),
                                      ),
                                      const SizedBox(height: 14),
                                      if (chapters != null && chapters.isNotEmpty)
                                        FilledButton.icon(
                                          onPressed: () => _open(chapters, _continueIndex(chapters)),
                                          icon: const Icon(Icons.play_arrow_rounded),
                                          label: Text(novels.started(work) ? 'Continuar' : 'Empezar'),
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
                else if (chapters == null)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else ...[
                  SliverList.list(children: rows),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 120),
                      child: Text(
                        'Mantén pulsado un capítulo para marcarlo como leído o no leído',
                        style: TextStyle(color: Kofu.muted, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

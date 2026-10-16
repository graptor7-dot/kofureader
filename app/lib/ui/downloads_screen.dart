import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/downloads.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'reader/reader_screen.dart';
import 'widgets/cover_card.dart';
import 'widgets/selection.dart';

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

/// Libros guardados en el dispositivo, agrupados por serie. Funciona sin conexión.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _selection = SelectionController<DownloadedBook>();

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

  KomgaReadProgress? _progress(DownloadManager downloads, DownloadedBook b) {
    final p = downloads.pendingProgress(b.sourceId, b.bookId);
    return p == null ? null : KomgaReadProgress(p.page, p.completed, null);
  }

  Future<void> _open(DownloadedBook book) async {
    final state = AppScope.read(context);
    final source = state.source(book.sourceId);
    if (source == null) {
      showToast(context, 'Ese servidor ya no está configurado', icon: Icons.error_outline);
      return;
    }
    final downloads = state.downloads;
    final series = downloads.ofSeries(book.sourceId, book.seriesId);
    final books = [for (final b in series) b.toKomgaBook(progress: _progress(downloads, b))];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReaderScreen(source: source, books: books, initialIndex: series.indexWhere((b) => b.bookId == book.bookId)),
      ),
    );
  }

  void _random(List<DownloadedBook> all) {
    final pool = _selection.active ? _selection.values : all;
    if (pool.isEmpty) return;
    _selection.clear();
    _open(pickRandom(pool));
  }

  Future<void> _confirmDelete(String title, String body, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) await action();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final downloads = state.downloads;
    // Las descargas de bibliotecas ocultas no se muestran.
    final all = downloads.all.where((b) => !state.isLibraryHidden(b.sourceId, b.libraryId)).toList();
    // Agrupar por serie.
    final groups = <String, List<DownloadedBook>>{};
    for (final b in all) {
      groups.putIfAbsent('${b.sourceId}|${b.seriesId}', () => []).add(b);
    }
    final seriesKeys = groups.keys.toList()
      ..sort(
        (a, b) => groups[a]!.first.seriesTitle.toLowerCase().compareTo(groups[b]!.first.seriesTitle.toLowerCase()),
      );

    return PopScope(
      canPop: !_selection.active,
      onPopInvokedWithResult: (didPop, _) => _selection.clear(),
      child: Scaffold(
        floatingActionButton: all.isEmpty
            ? null
            : RandomFab(onPressed: () => _random(all), selectedCount: _selection.count),
        appBar: _selection.active
            ? SelectionBar(
                count: _selection.count,
                onClose: _selection.clear,
                onSelectAll: () => _selection.selectAll({for (final b in all) b.key: b}),
                actions: [
                  IconButton(
                    tooltip: 'Borrar descargas',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _confirmDelete(
                      '¿Borrar ${_selection.count} descargas?',
                      'Se liberará espacio en este dispositivo. Siguen disponibles en Komga.',
                      () async {
                        for (final b in _selection.values) {
                          await downloads.delete(b.sourceId, b.bookId);
                        }
                        _selection.clear();
                      },
                    ),
                  ),
                ],
              )
            : null,
        body: CustomScrollView(
          slivers: [
            if (!_selection.active)
              SliverAppBar(
                pinned: true,
                expandedHeight: 170,
                actions: [
                  if (all.isNotEmpty)
                    PopupMenuButton<String>(
                      onSelected: (_) => _confirmDelete(
                        '¿Borrar todas las descargas?',
                        'Se borrarán ${all.length} libros (${formatBytes(downloads.totalBytes)}) de este dispositivo.',
                        downloads.deleteAll,
                      ),
                      itemBuilder: (_) => const [PopupMenuItem(value: 'all', child: Text('Borrar todo'))],
                    ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14, end: 56),
                  title: const Text('Descargas', style: TextStyle(fontWeight: FontWeight.w800)),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(-1, -1),
                            radius: 1.6,
                            colors: [Color(0x4434D399), Kofu.background],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 24,
                        bottom: 24,
                        child: Icon(
                          Icons.download_for_offline_rounded,
                          size: 96,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(child: _Summary(downloads: downloads)),
            if (all.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_for_offline_outlined, size: 56, color: Kofu.muted),
                        SizedBox(height: 12),
                        Text(
                          'Descarga libros desde la ficha de una serie (botón ⬇) para leerlos sin conexión',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Kofu.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              for (final key in seriesKeys) ..._seriesSection(state, groups[key]!),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  List<Widget> _seriesSection(AppState state, List<DownloadedBook> unsorted) {
    final first = unsorted.first;
    final books = state.downloads.ofSeries(first.sourceId, first.seriesId);
    final size = books.fold(0, (a, b) => a + b.sizeBytes);
    final source = state.source(first.sourceId);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
          child: Row(
            children: [
              if (source != null) ...[
                SourceChip(label: source.name, color: state.sourceColor(source.id)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  first.seriesTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Text(formatBytes(size), style: const TextStyle(color: Kofu.muted, fontSize: 12)),
              IconButton(
                tooltip: 'Borrar descargas de la serie',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: () => _confirmDelete(
                  '¿Borrar descargas de "${first.seriesTitle}"?',
                  '${books.length} libros, ${formatBytes(size)}.',
                  () async {
                    for (final b in books) {
                      await state.downloads.delete(b.sourceId, b.bookId);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.builder(
          gridDelegate: coverGridDelegate,
          itemCount: books.length,
          itemBuilder: (context, i) {
            final b = books[i];
            final cover = state.downloads.coverFile(b.sourceId, b.bookId);
            final p = state.downloads.pendingProgress(b.sourceId, b.bookId);
            return CoverCard(
              imageUrl: '',
              headers: const {},
              image: cover == null ? null : FileImage(cover),
              title: b.title,
              subtitle: '${b.pages.length} págs. · ${formatBytes(b.sizeBytes)}',
              read: p?.completed ?? false,
              progress: p == null || p.completed ? 0 : p.page / b.pages.length,
              downloaded: true,
              sourceColor: source == null ? null : state.sourceColor(source.id),
              selected: _selection.contains(b.key),
              selectionActive: _selection.active,
              onTap: _selection.active ? () => _selection.toggle(b.key, b) : () => _open(b),
              onLongPress: () => _selection.toggle(b.key, b),
            );
          },
        ),
      ),
    ];
  }
}

class _Summary extends StatelessWidget {
  final DownloadManager downloads;

  const _Summary({required this.downloads});

  @override
  Widget build(BuildContext context) {
    final queued = downloads.queuedCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Text(
            '${downloads.all.length} libros · ${formatBytes(downloads.totalBytes)}',
            style: const TextStyle(color: Kofu.muted),
          ),
          const Spacer(),
          if (queued > 0) ...[
            const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('$queued en cola', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextButton(onPressed: downloads.cancelAll, child: const Text('Cancelar')),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/snapshots.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'navigation.dart';
import 'widgets/cover_card.dart';

class _SeriesHit {
  final LibraryEntry entry;
  final KomgaSeries series;
  _SeriesHit(this.entry, this.series);
}

class _BookHit {
  final LibraryEntry entry;
  final KomgaBook book;
  _BookHit(this.entry, this.book);
}

/// Búsqueda en todas las bibliotecas visibles a la vez.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  String _query = '';
  List<_SeriesHit> _series = [];
  List<_BookHit> _books = [];
  final List<String> _errors = [];

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text.trim()));
  }

  Future<void> _search(String query) async {
    final gen = ++_generation;
    setState(() {
      _query = query;
      _errors.clear();
      if (query.isEmpty) {
        _series = [];
        _books = [];
      }
      _loading = query.isNotEmpty;
    });
    if (query.isEmpty) return;

    final state = AppScope.read(context);
    final groups = await state.loadAllLibraries();
    final entries = [
      for (final g in groups)
        for (final e in g.libraries)
          if (!state.isLibraryHidden(e.source.id, e.library.id)) e,
    ];
    final series = <_SeriesHit>[];
    final books = <_BookHit>[];
    final errors = <String>[];
    await Future.wait(
      entries.map((e) async {
        final client = state.client(e.source.id);
        try {
          final results = await Future.wait([
            client.series(libraryId: e.library.id, search: query, size: 30),
            client.searchBooks(libraryId: e.library.id, search: query),
          ]);
          series.addAll((results[0] as KomgaPage<KomgaSeries>).content.map((s) => _SeriesHit(e, s)));
          books.addAll((results[1] as List<KomgaBook>).map((b) => _BookHit(e, b)));
        } catch (_) {
          errors.add('${e.library.name} (${e.source.name})');
        }
      }),
    );
    if (!mounted || gen != _generation) return;
    // Primero lo que empieza por el texto buscado, luego alfabético.
    final q = query.toLowerCase();
    int rank(String title) => title.toLowerCase().startsWith(q) ? 0 : 1;
    series.sort((a, b) {
      final r = rank(a.series.title).compareTo(rank(b.series.title));
      return r != 0 ? r : a.series.title.toLowerCase().compareTo(b.series.title.toLowerCase());
    });
    // Los libros que ya aparecen por su serie no se repiten.
    final seriesIds = {for (final s in series) s.series.id};
    books.removeWhere((b) => seriesIds.contains(b.book.seriesId) && b.book.title == b.book.seriesTitle);
    setState(() {
      _series = series;
      _books = books;
      _errors.addAll(errors);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (t) => _search(t.trim()),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar en todas las bibliotecas',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        _search('');
                      },
                    ),
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          if (_loading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
          if (_errors.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  'Sin conexión con: ${_errors.join(', ')}',
                  style: const TextStyle(color: Kofu.muted, fontSize: 12),
                ),
              ),
            ),
          if (_query.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.travel_explore_rounded, size: 56, color: Kofu.muted),
                    SizedBox(height: 12),
                    Text('Busca series y libros en todos tus servidores', style: TextStyle(color: Kofu.muted)),
                  ],
                ),
              ),
            )
          else if (!_loading && _series.isEmpty && _books.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('Sin resultados', style: TextStyle(color: Kofu.muted)),
              ),
            )
          else ...[
            if (_series.isNotEmpty) _title('Series · ${_series.length}'),
            _grid(_series.length, (i) {
              final hit = _series[i];
              final client = state.client(hit.entry.source.id);
              final s = hit.series;
              return CoverCard(
                imageUrl: client.seriesThumbnailUrl(s.id),
                headers: client.authHeaders,
                title: s.title,
                subtitle: hit.entry.library.name,
                sourceColor: state.sourceColor(hit.entry.source.id),
                read: s.booksCount > 0 && s.booksUnreadCount == 0,
                favorite: state.data.isFavorite(s.snapshot(hit.entry.source.id).ref),
                onTap: () => openSeries(context, hit.entry.source, s.id, series: s),
              );
            }),
            if (_books.isNotEmpty) _title('Libros · ${_books.length}'),
            _grid(_books.length, (i) {
              final hit = _books[i];
              final client = state.client(hit.entry.source.id);
              final b = hit.book;
              return CoverCard(
                imageUrl: client.bookThumbnailUrl(b.id),
                headers: client.authHeaders,
                title: b.title,
                subtitle: b.seriesTitle,
                sourceColor: state.sourceColor(hit.entry.source.id),
                kindIcon: Icons.menu_book_rounded,
                read: b.isRead,
                progress: b.inProgress ? b.progressFraction : 0,
                onTap: () => openBook(context, hit.entry.source, b.id, seriesId: b.seriesId),
              );
            }),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ],
      ),
    );
  }

  Widget _title(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    ),
  );

  Widget _grid(int count, Widget Function(int) builder) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverGrid.builder(gridDelegate: coverGridDelegate, itemCount: count, itemBuilder: (_, i) => builder(i)),
  );
}

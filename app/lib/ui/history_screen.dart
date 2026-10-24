import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/source.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'navigation.dart';
import 'widgets/cover_card.dart';
import 'widgets/selection.dart' show FilterRow;

/// Lo que va cargando el historial de un servidor.
class _SourceCursor {
  final Source source;
  int nextPage = 0;
  bool done = false;
  final List<KomgaBook> books = [];

  _SourceCursor(this.source);
}

/// Historial de lectura: lo que Komga sabe que has leído (en cualquier dispositivo),
/// juntando todos los servidores y ordenado por fecha.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _pageSize = 40;
  final _scroll = ScrollController();
  List<_SourceCursor> _cursors = [];
  ReadStatus? _filter; // null = todo
  bool _loading = false;
  final List<String> _errors = [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _loadMore();
    });
    _reset();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final state = AppScope.read(context);
    setState(() {
      _cursors = [for (final s in state.sources.where((s) => state.hasSecret(s.id))) _SourceCursor(s)];
      _errors.clear();
    });
    await _loadMore();
  }

  /// Pide la siguiente página a cada servidor que aún tenga más.
  Future<void> _loadMore() async {
    if (_loading || _cursors.every((c) => c.done)) return;
    setState(() => _loading = true);
    final state = AppScope.read(context);
    final status = _filter == null ? null : {_filter!};
    await Future.wait(
      _cursors.where((c) => !c.done).map((c) async {
        try {
          final page = await state.client(c.source.id).readHistory(page: c.nextPage, size: _pageSize, status: status);
          c.books.addAll(page.content);
          c.nextPage++;
          c.done = page.last;
        } catch (_) {
          c.done = true;
          _errors.add(c.source.name);
        }
      }),
    );
    if (mounted) setState(() => _loading = false);
  }

  /// Une los servidores por fecha. Solo se muestra hasta donde todos han cargado,
  /// para que no aparezca algo antiguo antes que algo más reciente aún sin cargar.
  List<(Source, KomgaBook)> _merged(AppState state) {
    DateTime? horizon;
    for (final c in _cursors.where((c) => !c.done && c.books.isNotEmpty)) {
      final oldest = c.books.last.readDate;
      if (oldest != null && (horizon == null || oldest.isAfter(horizon))) horizon = oldest;
    }
    final all = [
      for (final c in _cursors)
        for (final b in c.books)
          if (!state.isLibraryHidden(c.source.id, b.libraryId) &&
              (horizon == null || !(b.readDate ?? DateTime(0)).isBefore(horizon)))
            (c.source, b),
    ]..sort((a, b) => (b.$2.readDate ?? DateTime(0)).compareTo(a.$2.readDate ?? DateTime(0)));
    return all;
  }

  static const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (diff < 7) return _weekdays[d.weekday - 1][0].toUpperCase() + _weekdays[d.weekday - 1].substring(1);
    return '${d.day} ${_months[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = _merged(state);
    // Si lo cargado no llena la pantalla (o queda oculto), seguir cargando.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _scroll.position.extentAfter < 600) _loadMore();
    });
    final rows = <Widget>[];
    String? lastDay;
    for (final (source, book) in items) {
      final date = book.readDate?.toLocal();
      final day = date == null ? 'Sin fecha' : _dayLabel(date);
      if (day != lastDay) {
        rows.add(_DayHeader(day));
        lastDay = day;
      }
      rows.add(_HistoryTile(source: source, book: book, date: date));
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _reset,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 150,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14),
                title: const Text('Historial', style: TextStyle(fontWeight: FontWeight.w800)),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-1, -1),
                          radius: 1.6,
                          colors: [Color(0x4438BDF8), Kofu.background],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 24,
                      bottom: 20,
                      child: Icon(Icons.history_rounded, size: 96, color: Colors.white.withValues(alpha: 0.1)),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: FilterRow(
                children: [
                  ChoiceChip(
                    label: const Text('Todo'),
                    selected: _filter == null,
                    onSelected: (_) {
                      _filter = null;
                      _reset();
                    },
                  ),
                  for (final s in [ReadStatus.inProgress, ReadStatus.read])
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _filter == s,
                      onSelected: (_) {
                        _filter = s;
                        _reset();
                      },
                    ),
                ],
              ),
            ),
            if (_errors.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'Sin conexión con: ${_errors.toSet().join(', ')}',
                    style: const TextStyle(color: Kofu.muted, fontSize: 12),
                  ),
                ),
              ),
            if (items.isEmpty && !_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 56, color: Kofu.muted),
                      SizedBox(height: 12),
                      Text('Aún no hay nada en el historial', style: TextStyle(color: Kofu.muted)),
                    ],
                  ),
                ),
              )
            else
              SliverList.list(children: rows),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: _loading ? const CircularProgressIndicator() : const SizedBox.shrink()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String text;

  const _DayHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
  );
}

class _HistoryTile extends StatelessWidget {
  final Source source;
  final KomgaBook book;
  final DateTime? date;

  const _HistoryTile({required this.source, required this.book, required this.date});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    final client = state.client(source.id);
    final time = date == null
        ? ''
        : '${date!.hour.toString().padLeft(2, '0')}:${date!.minute.toString().padLeft(2, '0')}';
    final status = book.isRead ? 'Leído' : 'Pág. ${book.readProgress?.page ?? 0} de ${book.pagesCount}';
    return InkWell(
      onTap: () => openBook(context, source, book.id, seriesId: book.seriesId),
      onLongPress: () => openSeries(context, source, book.seriesId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 54,
                height: 78,
                child: KomgaImage(url: client.bookThumbnailUrl(book.id), headers: client.authHeaders),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.seriesTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Kofu.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: state.sourceColor(source.id), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: book.isRead ? Kofu.read : Kofu.accent,
                        ),
                      ),
                      if (!book.isRead) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: book.progressFraction,
                              minHeight: 4,
                              color: Kofu.accent,
                              backgroundColor: Kofu.surfaceHigh,
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(time, style: const TextStyle(color: Kofu.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

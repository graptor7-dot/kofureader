import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../komga/models.dart';
import '../theme.dart';

/// Datos de lectura calculados a partir del historial.
class _Stats {
  final List<DateTime> chapters; // fecha de cada capítulo terminado (cómics y novelas)
  final int pages;
  final List<(String, int)> topSeries;

  _Stats(this.chapters, this.pages, this.topSeries);
}

/// Estadísticas de lectura: capítulos por semana, racha y series más leídas.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late final Future<_Stats> _future = _load();

  Future<_Stats> _load() async {
    final state = AppScope.read(context);
    final since = DateTime.now().subtract(const Duration(days: 180));
    final books = <KomgaBook>[];
    // Capítulos terminados de los últimos 6 meses en cada servidor.
    await Future.wait(
      state.sources.where((s) => state.hasSecret(s.id)).map((s) async {
        try {
          for (var page = 0; page < 10; page++) {
            final p = await state.client(s.id).readHistory(page: page, size: 100, status: {ReadStatus.read});
            final recent = p.content.where((b) => (b.readDate ?? DateTime(0)).isAfter(since)).toList();
            books.addAll(recent.where((b) => !state.isLibraryHidden(s.id, b.libraryId)));
            if (p.last || recent.length < p.content.length) break;
          }
        } catch (_) {}
      }),
    );
    final dates = [
      for (final b in books) b.readDate!.toLocal(),
      ...state.novels.readDates().where((d) => d.isAfter(since)),
    ];
    final bySeries = <String, int>{};
    for (final b in books) {
      bySeries[b.seriesTitle] = (bySeries[b.seriesTitle] ?? 0) + 1;
    }
    final top = bySeries.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return _Stats(dates, books.fold(0, (a, b) => a + b.pagesCount), top.take(5).toList());
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  int _streak(List<DateTime> dates) {
    final days = {for (final d in dates) _day(d)};
    var day = _day(DateTime.now());
    if (!days.contains(day)) day = day.subtract(const Duration(days: 1)); // aún no has leído hoy
    var streak = 0;
    while (days.contains(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 150,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14),
              title: const Text('Estadísticas', style: TextStyle(fontWeight: FontWeight.w800)),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-1, -1),
                        radius: 1.6,
                        colors: [Color(0x55F97316), Kofu.background],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 20,
                    child: Icon(Icons.insights_rounded, size: 96, color: Colors.white.withValues(alpha: 0.1)),
                  ),
                ],
              ),
            ),
          ),
          FutureBuilder<_Stats>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final s = snap.data!;
              final now = DateTime.now();
              final today = _day(now);
              final weekStart = today.subtract(Duration(days: today.weekday - 1));
              final monthStart = DateTime(now.year, now.month);
              int countSince(DateTime from) => s.chapters.where((d) => !d.isBefore(from)).length;
              // Últimas 12 semanas (de lunes a domingo).
              final weeks = [
                for (var i = 11; i >= 0; i--)
                  () {
                    final start = weekStart.subtract(Duration(days: 7 * i));
                    final end = start.add(const Duration(days: 7));
                    return (start, s.chapters.where((d) => !d.isBefore(start) && d.isBefore(end)).length);
                  }(),
              ];
              final maxWeek = weeks.fold(1, (a, w) => w.$2 > a ? w.$2 : a);

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                sliver: SliverList.list(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _StatTile('Hoy', '${countSince(today)}', 'capítulos', Kofu.accent),
                        _StatTile('Esta semana', '${countSince(weekStart)}', 'capítulos', Kofu.accent2),
                        _StatTile('Este mes', '${countSince(monthStart)}', 'capítulos', const Color(0xFF38BDF8)),
                        _StatTile('Racha', '${_streak(s.chapters)}', 'días seguidos', const Color(0xFFF97316)),
                        _StatTile('6 meses', '${s.pages}', 'páginas de cómic', const Color(0xFF34D399)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('Capítulos por semana', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 170,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final (i, (start, count)) in weeks.indexed)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (count > 0)
                                      Text('$count', style: const TextStyle(fontSize: 10, color: Kofu.muted)),
                                    const SizedBox(height: 4),
                                    AnimatedContainer(
                                      duration: Duration(milliseconds: 300 + i * 40),
                                      height: 4 + 120 * count / maxWeek,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        gradient: i == weeks.length - 1
                                            ? Kofu.accentGradient
                                            : LinearGradient(
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: [Kofu.accent2.withValues(alpha: 0.5), Kofu.accent2],
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${start.day}/${start.month}',
                                      style: const TextStyle(fontSize: 9, color: Kofu.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (s.topSeries.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const Text('Más leídas (6 meses)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 8),
                      for (final (i, (title, count)) in s.topSeries.indexed)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Kofu.surfaceHigh,
                            child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text('$count cap.', style: const TextStyle(color: Kofu.muted)),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatTile(this.label, this.value, this.unit, this.color);

  @override
  Widget build(BuildContext context) => Container(
    width: 160,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Kofu.surface,
      borderRadius: BorderRadius.circular(Kofu.radius + 4),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Kofu.muted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: color),
        ),
        Text(unit, style: const TextStyle(color: Kofu.muted, fontSize: 11)),
      ],
    ),
  );
}

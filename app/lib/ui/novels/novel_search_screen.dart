import 'package:flutter/material.dart';

import '../../data/app_scope.dart';
import '../../data/novels.dart';
import '../../theme.dart';

/// Buscar un texto dentro de una novela. Devuelve (capítulo, texto buscado) al elegir un resultado.
class NovelSearchScreen extends StatefulWidget {
  final NovelWork work;

  const NovelSearchScreen({super.key, required this.work});

  @override
  State<NovelSearchScreen> createState() => _NovelSearchScreenState();
}

class _NovelSearchScreenState extends State<NovelSearchScreen> {
  final _controller = TextEditingController();
  Future<NovelSearchResult>? _future;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _controller.text.trim();
    if (q.length < 2) return;
    setState(() {
      _query = q;
      _future = AppScope.read(context).novels.search(widget.work, q);
    });
  }

  /// "…texto [[coincidencia]] texto…" con la coincidencia resaltada.
  Widget _snippet(String s) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\[\[(.*?)\]\]');
    var last = 0;
    for (final m in re.allMatches(s)) {
      spans.add(TextSpan(text: s.substring(last, m.start)));
      spans.add(
        TextSpan(
          text: m.group(1),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            background: Paint()..color = Kofu.accent.withValues(alpha: 0.45),
          ),
        ),
      );
      last = m.end;
    }
    spans.add(TextSpan(text: s.substring(last)));
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(color: Kofu.muted, fontSize: 13, height: 1.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Buscar en ${widget.work.title}',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [IconButton(onPressed: _submit, icon: const Icon(Icons.search_rounded))],
      ),
      body: _future == null
          ? const _Hint(
              icon: Icons.manage_search_rounded,
              text: 'Escribe una palabra o frase.\nSe busca en todos los capítulos, sin importar mayúsculas ni tildes.',
            )
          : FutureBuilder<NovelSearchResult>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) return _Hint(icon: Icons.error_outline_rounded, text: '${snap.error}');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final r = snap.data!;
                if (r.hits.isEmpty) return _Hint(icon: Icons.search_off_rounded, text: 'No aparece "$_query"');
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 40),
                  itemCount: r.hits.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Text(
                          '${r.total} coincidencia${r.total == 1 ? '' : 's'} en ${r.hits.length} '
                          'capítulo${r.hits.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      );
                    }
                    final h = r.hits[i - 1];
                    return InkWell(
                      onTap: () => Navigator.pop(context, (h.chapterId, _query)),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Kofu.surface,
                          borderRadius: BorderRadius.circular(Kofu.radius),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (h.number != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      '${h.number}',
                                      style: const TextStyle(color: Kofu.accent, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    h.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Kofu.surfaceHigh,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('×${h.count}', style: const TextStyle(fontSize: 12, color: Kofu.muted)),
                                ),
                              ],
                            ),
                            for (final s in h.snippets) ...[const SizedBox(height: 8), _snippet(s)],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Kofu.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Kofu.muted),
          ),
        ],
      ),
    ),
  );
}

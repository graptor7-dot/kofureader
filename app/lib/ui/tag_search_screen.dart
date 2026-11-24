import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/comic_tags.dart';
import '../data/snapshots.dart';
import '../komga/models.dart';
import '../theme.dart';
import 'navigation.dart';
import 'widgets/cover_card.dart';

/// Busca capítulos sueltos de una biblioteca por nombre y por los tags de sus archivos
/// (ComicInfo.xml). Con varios tags, solo salen los capítulos que los tienen todos.
class TagSearchScreen extends StatefulWidget {
  final LibraryEntry entry;

  const TagSearchScreen({super.key, required this.entry});

  @override
  State<TagSearchScreen> createState() => _TagSearchScreenState();
}

class _TagSearchScreenState extends State<TagSearchScreen> {
  final _name = TextEditingController();
  final _tagInput = TextEditingController();
  final _tagFocus = FocusNode();
  final _selected = <String>[];
  ComicTagIndex? _index;
  String? _error;
  List<KomgaBook> _results = [];
  Timer? _debounce;

  List<String>? get _allTags => _index?.allTags;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _tagInput.dispose();
    _tagFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _error = null);
    try {
      final index = await ComicTagIndex.load(
        AppScope.read(context),
        widget.entry.source.id,
        widget.entry.library.id,
        force: force,
      );
      if (!mounted) return;
      setState(() => _index = index);
      _search();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  bool get _hasQuery => _selected.isNotEmpty || _name.text.trim().isNotEmpty;

  void _queue() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  void _search() {
    final index = _index;
    setState(() => _results = index == null || !_hasQuery ? [] : index.search(_name.text, _selected));
  }

  void _addTag(String tag) {
    if (_selected.contains(tag)) return;
    setState(() {
      _selected.add(tag);
      _tagInput.clear();
    });
    _tagFocus.requestFocus();
    _search();
  }

  void _removeTag(String tag) {
    setState(() => _selected.remove(tag));
    _search();
  }

  List<String> get _suggestions {
    final all = _allTags ?? const <String>[];
    final q = _tagInput.text.trim().toLowerCase();
    final pool = all.where((t) => !_selected.contains(t));
    if (q.isEmpty) return pool.toList();
    // Primero los que empiezan por lo escrito, luego los que lo contienen.
    final starts = pool.where((t) => t.toLowerCase().startsWith(q));
    final contains = pool.where((t) => !t.toLowerCase().startsWith(q) && t.toLowerCase().contains(q));
    return [...starts, ...contains];
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final client = state.client(widget.entry.source.id);
    final suggestions = _suggestions;
    final typing = _tagInput.text.trim().isNotEmpty;
    final shown = suggestions.take(typing ? 40 : 60).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Buscar por tags', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(widget.entry.library.name, style: const TextStyle(fontSize: 12, color: Kofu.muted)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => _queue(),
                      decoration: _fieldDecoration(
                        hint: 'Nombre del capítulo',
                        icon: Icons.search_rounded,
                        onClear: _name.text.isEmpty
                            ? null
                            : () {
                                _name.clear();
                                _search();
                              },
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tagInput,
                      focusNode: _tagFocus,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (suggestions.isNotEmpty) _addTag(suggestions.first);
                      },
                      decoration: _fieldDecoration(
                        hint: _allTags == null
                            ? 'Cargando tags…'
                            : 'Añadir tag (${_allTags!.length} en esta biblioteca)',
                        icon: Icons.label_rounded,
                        onClear: _tagInput.text.isEmpty ? null : () => setState(_tagInput.clear),
                      ),
                    ),
                    if (_selected.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in _selected)
                            InputChip(
                              label: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                              avatar: const Icon(Icons.label_rounded, size: 16, color: Colors.white),
                              backgroundColor: Kofu.accent.withValues(alpha: 0.85),
                              side: BorderSide.none,
                              deleteIconColor: Colors.white,
                              labelStyle: const TextStyle(color: Colors.white),
                              onDeleted: () => _removeTag(t),
                            ),
                          if (_selected.length > 1)
                            ActionChip(
                              label: const Text('Quitar todos'),
                              onPressed: () {
                                setState(_selected.clear);
                                _search();
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_index?.scanning ?? false)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          'KofuSync todavía está leyendo los archivos: faltan tags. Desliza hacia abajo para actualizar.',
                          style: TextStyle(color: Kofu.gold, fontSize: 13),
                        ),
                      ),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Kofu.muted))
                    else if (_allTags != null && _allTags!.isEmpty)
                      Text(
                        _index!.kofusync
                            ? 'Los archivos de esta biblioteca aún no tienen tags.'
                            : 'Sin tags: actualiza KofuSync y dale la carpeta de estos archivos.',
                        style: const TextStyle(color: Kofu.muted),
                      )
                    else if (shown.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 132),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in shown)
                                ActionChip(
                                  label: Text(t),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _addTag(t),
                                ),
                              if (suggestions.length > shown.length)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  child: Text(
                                    '+${suggestions.length - shown.length} más · escribe para filtrar',
                                    style: const TextStyle(color: Kofu.muted, fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else if (typing)
                      const Text('Ningún tag coincide', style: TextStyle(color: Kofu.muted)),
                    const SizedBox(height: 6),
                    const Divider(),
                    if (_hasQuery && _index != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _results.isEmpty ? 'Ningún capítulo coincide' : _countLabel,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!_hasQuery)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.label_rounded, size: 48, color: Kofu.muted),
                        SizedBox(height: 12),
                        Text(
                          'Elige uno o varios tags, o escribe un nombre.\n'
                          'Con varios tags salen solo los capítulos que los tienen todos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Kofu.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                sliver: CoverSliverGrid(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final b = _results[i];
                    return CoverCard(
                      imageUrl: client.bookThumbnailUrl(b.id),
                      headers: client.authHeaders,
                      title: b.title,
                      subtitle: b.seriesTitle,
                      read: b.isRead,
                      progress: b.inProgress ? b.progressFraction : 0,
                      favorite: state.data.isFavorite(b.snapshot(widget.entry.source.id).ref),
                      gone: b.deleted || state.isGone(widget.entry.source.id, b.id),
                      onTap: () => openBook(context, widget.entry.source, b.id, seriesId: b.seriesId),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                child: Center(
                  child: _index == null && _error == null
                      ? const Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Leyendo los capítulos de la biblioteca…', style: TextStyle(color: Kofu.muted)),
                          ],
                        )
                      : _error != null
                      ? TextButton(onPressed: _load, child: const Text('Reintentar'))
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _countLabel {
    final n = _results.length;
    return '$n capítulo${n == 1 ? '' : 's'}';
  }

  InputDecoration _fieldDecoration({required String hint, required IconData icon, VoidCallback? onClear}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: onClear == null ? null : IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded)),
        filled: true,
        fillColor: Kofu.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Kofu.radius), borderSide: BorderSide.none),
      );
}

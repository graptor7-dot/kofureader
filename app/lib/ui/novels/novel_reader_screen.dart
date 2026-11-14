import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/app_scope.dart';
import '../../data/novels.dart';
import '../../data/user_data.dart';
import '../../theme.dart';
import '../desktop.dart';

/// Tema de lectura de novelas (guardado por dispositivo).
enum NovelTheme {
  dark('Oscuro', Color(0xFF0C0C11), Color(0xFFE4E4EC)),
  black('Negro', Color(0xFF000000), Color(0xFFC9C9D2)),
  sepia('Sepia', Color(0xFFF3EAD3), Color(0xFF3B2F21)),
  light('Claro', Color(0xFFFAFAF7), Color(0xFF1C1C1E));

  final String label;
  final Color background;
  final Color text;
  const NovelTheme(this.label, this.background, this.text);

  bool get isLight => this == sepia || this == light;
}

/// Ajustes del lector de novelas, en preferencias locales.
class NovelReaderSettings {
  final UserData data;

  NovelReaderSettings(this.data);

  double get fontSize => double.tryParse(data.localPref('novel_font_size') ?? '') ?? 19;
  set fontSize(double v) => data.setLocalPref('novel_font_size', v.toStringAsFixed(1));

  double get lineHeight => double.tryParse(data.localPref('novel_line_height') ?? '') ?? 1.65;
  set lineHeight(double v) => data.setLocalPref('novel_line_height', v.toStringAsFixed(2));

  bool get serif => data.localPref('novel_serif') != '0';
  set serif(bool v) => data.setLocalPref('novel_serif', v ? null : '0');

  NovelTheme get theme => NovelTheme.values.asNameMap()[data.localPref('novel_theme')] ?? NovelTheme.dark;
  set theme(NovelTheme v) => data.setLocalPref('novel_theme', v.name);

  TextStyle style() {
    final base = TextStyle(fontSize: fontSize, height: lineHeight, color: theme.text);
    return serif ? GoogleFonts.getFont('Literata', textStyle: base) : base;
  }
}

/// Un bloque del texto: párrafo, título o separador.
class NovelBlock {
  final String text;
  final bool heading;
  final bool separator;

  NovelBlock(this.text, {this.heading = false, this.separator = false});
}

/// Divide el texto en párrafos. Si hay líneas en blanco, separan párrafos;
/// si no, cada línea es un párrafo. Entiende los títulos "#" de Markdown.
List<NovelBlock> parseNovelText(String raw) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  final hasBlankLines = RegExp(r'\n\s*\n').hasMatch(text);
  final parts = hasBlankLines ? text.split(RegExp(r'\n\s*\n')) : text.split('\n');
  final blocks = <NovelBlock>[];
  for (var p in parts) {
    p = p.trim();
    if (p.isEmpty) continue;
    if (RegExp(r'^([*\-_~=]\s*){3,}$').hasMatch(p)) {
      blocks.add(NovelBlock('', separator: true));
      continue;
    }
    final heading = RegExp(r'^#{1,6}\s+').firstMatch(p);
    if (heading != null) {
      blocks.add(NovelBlock(p.substring(heading.end).trim(), heading: true));
      continue;
    }
    blocks.add(NovelBlock(p.replaceAll('**', '').replaceAll('__', '')));
  }
  return blocks;
}

/// Lector de texto para novelas.
class NovelReaderScreen extends StatefulWidget {
  final NovelWork work;
  final List<NovelChapter> chapters;
  final int initialIndex;

  const NovelReaderScreen({super.key, required this.work, required this.chapters, required this.initialIndex});

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends State<NovelReaderScreen> {
  late int _index = widget.initialIndex;
  final _scroll = ScrollController();
  final _focus = FocusNode();
  List<NovelBlock>? _blocks;
  String? _error;
  bool _overlay = false;
  double _fraction = 0;
  Timer? _saveTimer;

  NovelChapter get _chapter => widget.chapters[_index];
  bool get _hasNext => _index < widget.chapters.length - 1;
  bool get _hasPrev => _index > 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _openChapter(_index);
  }

  @override
  void dispose() {
    _savePosition();
    WakelockPlus.disable().catchError((_) {});
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openChapter(int index) async {
    _savePosition();
    setState(() {
      _index = index;
      _blocks = null;
      _error = null;
      _fraction = 0;
    });
    final novels = AppScope.read(context).novels;
    try {
      final text = await novels.chapterText(widget.work, widget.chapters[index]);
      if (!mounted || index != _index) return;
      setState(() => _blocks = parseNovelText(text));
      // Volver a donde se dejó (si no estaba ya leído entero).
      final chapter = widget.chapters[index];
      final saved = novels.isRead(widget.work, chapter) ? 0.0 : (novels.position(widget.work, chapter) ?? 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo((_scroll.position.maxScrollExtent * saved).clamp(0, _scroll.position.maxScrollExtent));
        novels.savePosition(widget.work, chapter, saved); // marca este capítulo como el último abierto
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final f = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((f - _fraction).abs() > 0.005) setState(() => _fraction = f);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _savePosition);
  }

  void _savePosition() {
    _saveTimer?.cancel();
    if (_blocks == null) return;
    AppScope.read(context).novels.savePosition(widget.work, _chapter, _fraction);
  }

  void _scrollBy(double fraction) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + fraction * _scroll.position.viewportDimension).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _scrollBy(0.3);
      case LogicalKeyboardKey.arrowUp:
        _scrollBy(-0.3);
      case LogicalKeyboardKey.space || LogicalKeyboardKey.pageDown:
        _scrollBy(0.85);
      case LogicalKeyboardKey.pageUp:
        _scrollBy(-0.85);
      case LogicalKeyboardKey.arrowRight:
        if (_hasNext) _openChapter(_index + 1);
      case LogicalKeyboardKey.arrowLeft:
        if (_hasPrev) _openChapter(_index - 1);
      case LogicalKeyboardKey.escape:
        Navigator.maybePop(context);
      case LogicalKeyboardKey.f11:
        toggleFullScreen();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _showSettings() async {
    final settings = NovelReaderSettings(AppScope.read(context).data);
    await showModalBottomSheet(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void update(VoidCallback f) {
            f();
            setSheet(() {});
            setState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lectura', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in NovelTheme.values)
                        ChoiceChip(
                          avatar: CircleAvatar(backgroundColor: t.background, radius: 8),
                          label: Text(t.label),
                          selected: settings.theme == t,
                          onSelected: (_) => update(() => settings.theme = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.format_size_rounded, color: Kofu.muted),
                      Expanded(
                        child: Slider(
                          min: 14,
                          max: 32,
                          divisions: 18,
                          value: settings.fontSize.clamp(14, 32),
                          label: settings.fontSize.round().toString(),
                          onChanged: (v) => update(() => settings.fontSize = v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.format_line_spacing_rounded, color: Kofu.muted),
                      Expanded(
                        child: Slider(
                          min: 1.3,
                          max: 2.2,
                          divisions: 9,
                          value: settings.lineHeight.clamp(1.3, 2.2),
                          onChanged: (v) => update(() => settings.lineHeight = v),
                        ),
                      ),
                    ],
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Con serifa')),
                      ButtonSegment(value: false, label: Text('Sin serifa')),
                    ],
                    selected: {settings.serif},
                    onSelectionChanged: (s) => update(() => settings.serif = s.first),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = NovelReaderSettings(AppScope.of(context).data);
    final theme = settings.theme;
    final style = settings.style();
    final muted = theme.text.withValues(alpha: 0.55);
    final blocks = _blocks;

    Widget body;
    if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: theme.text),
              textAlign: TextAlign.center,
            ),
            TextButton(onPressed: () => _openChapter(_index), child: const Text('Reintentar')),
          ],
        ),
      );
    } else if (blocks == null) {
      body = Center(child: CircularProgressIndicator(color: theme.isLight ? Kofu.accent2 : Kofu.accent));
    } else {
      body = SingleChildScrollView(
        controller: _scroll,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 32, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.work.title,
                    style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _chapter.label,
                    style: style.copyWith(fontSize: style.fontSize! * 1.35, fontWeight: FontWeight.w800, height: 1.25),
                  ),
                  SizedBox(height: style.fontSize! * 1.4),
                  for (final b in blocks)
                    if (b.separator)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: style.fontSize!),
                        child: Center(
                          child: Text('⁂', style: style.copyWith(color: muted)),
                        ),
                      )
                    else if (b.heading)
                      Padding(
                        padding: EdgeInsets.only(top: style.fontSize! * 0.8, bottom: style.fontSize! * 0.6),
                        child: Text(
                          b.text,
                          style: style.copyWith(fontWeight: FontWeight.w800, fontSize: style.fontSize! * 1.15),
                        ),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.only(bottom: style.fontSize! * 0.8),
                        child: Text(b.text, style: style, textAlign: TextAlign.justify),
                      ),
                  const SizedBox(height: 40),
                  _ChapterEnd(
                    theme: theme,
                    finished: _chapter,
                    next: _hasNext ? widget.chapters[_index + 1] : null,
                    onNext: () => _openChapter(_index + 1),
                    onExit: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: theme.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(onTap: () => setState(() => _overlay = !_overlay), child: body),
            ),
            // Barra fina de progreso del capítulo.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: _fraction,
                minHeight: 2,
                color: Kofu.accent,
                backgroundColor: Colors.transparent,
              ),
            ),
            if (_overlay) ..._overlayBars(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _overlayBars(NovelTheme theme) {
    final barColor = theme.isLight ? Colors.white.withValues(alpha: 0.95) : Colors.black.withValues(alpha: 0.85);
    final fg = theme.isLight ? Colors.black87 : Colors.white;
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: barColor,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                BackButton(color: fg),
                Expanded(
                  child: Text(
                    _chapter.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 16),
                  ),
                ),
                IconButton(
                  tooltip: 'Ajustes de lectura',
                  onPressed: _showSettings,
                  icon: Icon(Icons.text_fields_rounded, color: fg),
                ),
                if (isDesktop)
                  IconButton(
                    tooltip: 'Pantalla completa (F11)',
                    onPressed: toggleFullScreen,
                    icon: Icon(Icons.fullscreen_rounded, color: fg),
                  ),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Material(
          color: barColor,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Capítulo anterior',
                    onPressed: _hasPrev ? () => _openChapter(_index - 1) : null,
                    icon: Icon(Icons.skip_previous_rounded, color: _hasPrev ? fg : fg.withValues(alpha: 0.3)),
                  ),
                  Expanded(
                    child: Text(
                      'Capítulo ${_index + 1} de ${widget.chapters.length} · ${(_fraction * 100).round()} %',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: fg),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Capítulo siguiente',
                    onPressed: _hasNext ? () => _openChapter(_index + 1) : null,
                    icon: Icon(Icons.skip_next_rounded, color: _hasNext ? fg : fg.withValues(alpha: 0.3)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _ChapterEnd extends StatelessWidget {
  final NovelTheme theme;
  final NovelChapter finished;
  final NovelChapter? next;
  final VoidCallback onNext;
  final VoidCallback onExit;

  const _ChapterEnd({
    required this.theme,
    required this.finished,
    required this.next,
    required this.onNext,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final muted = theme.text.withValues(alpha: 0.55);
    final next = this.next;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Text('⁂', style: TextStyle(color: muted, fontSize: 24)),
            const SizedBox(height: 16),
            Text(
              'Fin de «${finished.title}»',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            if (next != null)
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded),
                label: Text('Siguiente: ${next.title}', overflow: TextOverflow.ellipsis),
              )
            else
              Text(
                'Era el último capítulo',
                style: TextStyle(color: theme.text, fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 10),
            TextButton(onPressed: onExit, child: const Text('Salir')),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/app_scope.dart';
import '../data/remote_hub.dart';
import '../theme.dart';
import 'widgets/selection.dart' show showToast;

/// Modo mando: el móvil controla el lector abierto en otro dispositivo o en la tele.
class RemoteScreen extends StatefulWidget {
  /// Pantalla a la que conectarse directamente (p. ej. la tele tras enviarle un libro).
  final String? focus;

  const RemoteScreen({super.key, this.focus});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  late final RemoteHub _hub = AppScope.read(context).remote;
  late String? _selectedId = widget.focus;

  RemoteScreenInfo? get _selected => _selectedId == null ? null : _hub.screen(_selectedId!);

  @override
  void initState() {
    super.initState();
    _hub.acquire();
    _hub.addListener(_onHub);
    if (_selectedId != null) _hub.attach(_selectedId!);
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _hub.removeListener(_onHub);
    _hub.release();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  bool _hadSelected = false;

  void _onHub() {
    if (!mounted) return;
    final lost = _hadSelected && _selected == null && _hub.received;
    _hadSelected = _selected != null;
    setState(() {
      if (lost) _selectedId = null;
    });
    if (lost) showToast(context, 'La pantalla se ha desconectado', icon: Icons.tv_off_rounded);
  }

  void _connect(RemoteScreenInfo s) {
    // Una tele sin nada abierto: directamente a elegir qué leer.
    if (s.isTv && !s.hasBook) {
      _choose(s.deviceId);
      return;
    }
    setState(() => _selectedId = s.deviceId);
    _hub.attach(s.deviceId);
    HapticFeedback.mediumImpact();
  }

  /// Vuelve al inicio para elegir un libro; al tocarlo se abrirá en la tele.
  void _choose(String tvId) {
    _hub.startChoosing(tvId);
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  void _send(String cmd, [Map<String, dynamic> args = const {}]) {
    final s = _selected;
    if (s == null) return;
    // En la tele los capítulos los gestiona el móvil (la tele no conoce la serie).
    if (s.isTv) {
      final session = _hub.tvSession;
      final ownsBook = session != null && session.tvId == s.deviceId;
      if (cmd == 'nextChapter' || (cmd == 'next' && s.atEnd)) {
        if (ownsBook && session.hasNext) _guard(_hub.tvNextChapter());
        return;
      }
      if (cmd == 'prevChapter') {
        if (ownsBook && session.hasPrev) _guard(_hub.tvPrevChapter());
        return;
      }
      if (cmd == 'exit') {
        ownsBook ? _hub.tvClose() : _hub.command(s.deviceId, 'exit');
        setState(() => _selectedId = null);
        return;
      }
    }
    _hub.command(s.deviceId, cmd, args);
  }

  Future<void> _guard(Future<void> f) async {
    try {
      await f;
    } catch (e) {
      if (mounted) showToast(context, '$e', icon: Icons.error_outline);
    }
  }

  Future<void> _pairTv() async {
    final code = await showDialog<String>(context: context, builder: (_) => const _PairDialog());
    if (code == null || !mounted) return;
    final id = await _hub.pairTv(code);
    if (!mounted) return;
    if (id == null) {
      showToast(context, 'Código incorrecto o caducado', icon: Icons.error_outline);
    } else {
      showToast(context, 'Tele emparejada', icon: Icons.tv_rounded);
      _choose(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final session = _hub.tvSession;
    final tvOwned = selected != null && selected.isTv && session?.tvId == selected.deviceId;
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selectedId = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(selected == null ? 'Modo mando' : selected.name),
          actions: [
            if (selected != null && selected.isTv)
              TextButton.icon(
                onPressed: () => _choose(selected.deviceId),
                icon: const Icon(Icons.library_books_rounded),
                label: const Text('Elegir otro'),
              ),
            if (selected != null)
              IconButton(
                tooltip: 'Desconectar',
                onPressed: () => setState(() => _selectedId = null),
                icon: const Icon(Icons.link_off_rounded),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: !_hub.available
            ? const _Message(
                icon: Icons.cloud_off_rounded,
                text: 'El modo mando usa KofuSync.\nConfigúralo en Ajustes → Sincronización.',
              )
            : selected != null
            ? _Controller(
                screen: selected,
                send: _send,
                hasNext: tvOwned ? session!.hasNext : selected.hasNext,
                hasPrev: tvOwned ? session!.hasPrev : selected.hasPrev,
              )
            : _ScreenList(
                screens: _hub.others,
                loading: !_hub.received,
                error: _hub.connected ? null : _hub.error,
                onTap: _connect,
                onPairTv: _pairTv,
              ),
      ),
    );
  }
}

/// Pide el código de 4 cifras que muestra la tele.
class _PairDialog extends StatefulWidget {
  const _PairDialog();

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void submit() {
      if (_controller.text.trim().length == 4) Navigator.pop(context, _controller.text.trim());
    }

    return AlertDialog(
      title: const Text('Añadir tele'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'En el navegador de la tele abre la dirección de KofuSync terminada en /tv '
            '(por ejemplo http://192.168.1.29:49200/tv) y escribe aquí el código que aparece.',
            style: TextStyle(color: Kofu.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 12),
            decoration: const InputDecoration(counterText: '', hintText: '0000'),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: submit, child: const Text('Emparejar')),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? extra;

  const _Message({required this.icon, required this.text, this.extra});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Kofu.muted),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Kofu.muted, height: 1.4),
          ),
          if (extra != null) ...[const SizedBox(height: 20), extra!],
        ],
      ),
    ),
  );
}

class _ScreenList extends StatelessWidget {
  final List<RemoteScreenInfo> screens;
  final bool loading;
  final String? error;
  final ValueChanged<RemoteScreenInfo> onTap;
  final VoidCallback onPairTv;

  const _ScreenList({
    required this.screens,
    required this.loading,
    required this.error,
    required this.onTap,
    required this.onPairTv,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) return _Message(icon: Icons.wifi_off_rounded, text: error!);
    if (loading) return const Center(child: CircularProgressIndicator());
    final pairButton = OutlinedButton.icon(
      onPressed: onPairTv,
      icon: const Icon(Icons.tv_rounded),
      label: const Text('Añadir tele'),
    );
    if (screens.isEmpty) {
      return _Message(
        icon: Icons.tv_rounded,
        text: 'Abre un cómic en el PC, o la web de KofuSync en la tele, y aparecerá aquí.',
        extra: pairButton,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text('Pantallas disponibles', style: TextStyle(color: Kofu.muted)),
        ),
        for (final s in screens)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Kofu.surface,
              borderRadius: BorderRadius.circular(Kofu.radius + 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(Kofu.radius + 4),
                onTap: () => onTap(s),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: Kofu.accentGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          s.isTv
                              ? Icons.tv_rounded
                              : s.name == 'PC'
                              ? Icons.desktop_windows_rounded
                              : Icons.tablet_mac_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                            const SizedBox(height: 2),
                            Text(
                              !s.hasBook
                                  ? 'Toca para elegir qué leer'
                                  : s.series.isEmpty
                                  ? s.title
                                  : '${s.series} · ${s.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Kofu.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Icon(s.hasBook ? Icons.settings_remote_rounded : Icons.library_add_rounded, color: Kofu.accent),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Center(child: pairButton),
      ],
    );
  }
}

/// El mando en sí: zonas grandes para pasar páginas, o trackpad en vertical.
class _Controller extends StatelessWidget {
  final RemoteScreenInfo screen;
  final void Function(String cmd, [Map<String, dynamic> args]) send;
  final bool hasNext;
  final bool hasPrev;

  const _Controller({required this.screen, required this.send, required this.hasNext, required this.hasPrev});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          _StatusStrip(screen: screen),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: screen.vertical ? _Trackpad(send: send) : _PageZones(rtl: screen.rtl, send: send),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                _BarButton(
                  icon: Icons.skip_previous_rounded,
                  label: 'Cap. anterior',
                  onTap: hasPrev ? () => send('prevChapter') : null,
                ),
                _BarButton(icon: Icons.menu_rounded, label: 'Menú', onTap: () => send('overlay')),
                _BarButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Cap. siguiente',
                  onTap: hasNext ? () => send('nextChapter') : null,
                ),
                _BarButton(icon: Icons.close_rounded, label: 'Salir', onTap: () => send('exit')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  final RemoteScreenInfo screen;

  const _StatusStrip({required this.screen});

  @override
  Widget build(BuildContext context) {
    final progress = screen.total > 0 ? screen.page / screen.total : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (screen.series.isNotEmpty)
            Text(
              screen.series,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Kofu.muted),
            ),
          Text(
            screen.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    color: Kofu.accent,
                    backgroundColor: Kofu.surfaceHigh,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Pág. ${screen.page} / ${screen.total}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dos zonas grandes: anterior / siguiente. En manga (RTL) "siguiente" va a la izquierda.
class _PageZones extends StatelessWidget {
  final bool rtl;
  final void Function(String cmd, [Map<String, dynamic> args]) send;

  const _PageZones({required this.rtl, required this.send});

  @override
  Widget build(BuildContext context) {
    final next = _Zone(
      icon: rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      label: 'Siguiente',
      primary: true,
      onTap: () => send('next'),
    );
    final prev = _Zone(
      icon: rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
      label: 'Anterior',
      primary: false,
      onTap: () => send('prev'),
    );
    return Row(
      children: [
        Expanded(child: rtl ? next : prev),
        const SizedBox(width: 12),
        Expanded(child: rtl ? prev : next),
      ],
    );
  }
}

class _Zone extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _Zone({required this.icon, required this.label, required this.primary, required this.onTap});

  @override
  State<_Zone> createState() => _ZoneState();
}

class _ZoneState extends State<_Zone> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(28);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: widget.primary
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Kofu.accent.withValues(alpha: _pressed ? 0.55 : 0.35),
                      Kofu.accent2.withValues(alpha: _pressed ? 0.45 : 0.25),
                    ],
                  )
                : null,
            color: widget.primary ? null : (_pressed ? Kofu.surfaceHigh : Kofu.surface),
            border: Border.all(color: widget.primary ? Kofu.accent.withValues(alpha: 0.6) : Kofu.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 72, color: widget.primary ? Colors.white : Kofu.muted),
              Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: widget.primary ? Colors.white : Kofu.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trackpad para el modo vertical: deslizar el dedo desplaza el lector del PC.
class _Trackpad extends StatefulWidget {
  final void Function(String cmd, [Map<String, dynamic> args]) send;

  const _Trackpad({required this.send});

  @override
  State<_Trackpad> createState() => _TrackpadState();
}

class _TrackpadState extends State<_Trackpad> {
  static const _gain = 1.6; // mover medio móvil ≈ casi una pantalla del PC
  double _pending = 0;
  Timer? _flush;
  bool _touching = false;

  @override
  void dispose() {
    _flush?.cancel();
    super.dispose();
  }

  void _queue(double fraction) {
    _pending += fraction;
    // Se agrupan los movimientos (~60 por segundo) para no saturar la red.
    _flush ??= Timer(const Duration(milliseconds: 16), () {
      _flush = null;
      if (_pending.abs() > 0.0005) widget.send('scroll', {'dy': _pending});
      _pending = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _touching = true),
          // Dedo hacia arriba = bajar en el lector, como al hacer scroll con el dedo.
          onVerticalDragUpdate: (d) => _queue(-d.delta.dy / height * _gain),
          onVerticalDragEnd: (d) {
            setState(() => _touching = false);
            widget.send('fling', {'v': -d.velocity.pixelsPerSecond.dy / height * _gain});
          },
          onVerticalDragCancel: () => setState(() => _touching = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: _touching ? Kofu.surfaceHigh : Kofu.surface,
              border: Border.all(color: _touching ? Kofu.accent : Kofu.outline, width: _touching ? 2 : 1),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swipe_vertical_rounded, size: 64, color: _touching ? Kofu.accent : Kofu.muted),
                  const SizedBox(height: 12),
                  const Text(
                    'Desliza para desplazar',
                    style: TextStyle(color: Kofu.muted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BarButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? Kofu.outline : Colors.white;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

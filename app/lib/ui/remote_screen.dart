import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/app_scope.dart';
import '../data/remote_link.dart';
import '../theme.dart';
import 'widgets/selection.dart' show showToast;

/// Una pantalla (dispositivo con el lector abierto) vista desde el mando.
class _Screen {
  final String deviceId;
  final String name;
  final String title;
  final String series;
  final int page;
  final int total;
  final String mode;
  final bool hasNext;
  final bool hasPrev;

  _Screen(Map<String, dynamic> j)
    : deviceId = '${j['deviceId']}',
      name = '${j['name'] ?? 'Pantalla'}',
      title = '${j['title'] ?? ''}',
      series = '${j['series'] ?? ''}',
      page = (j['page'] as num?)?.toInt() ?? 0,
      total = (j['total'] as num?)?.toInt() ?? 0,
      mode = '${j['mode'] ?? 'pagedRtl'}',
      hasNext = j['hasNext'] == true,
      hasPrev = j['hasPrev'] == true;

  bool get vertical => mode == 'vertical';
  bool get rtl => mode == 'pagedRtl';
}

/// Modo mando: el móvil controla el lector abierto en otro dispositivo.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  RemoteLink? _link;
  List<_Screen> _screens = [];
  bool _received = false;
  String? _selectedId;
  String? _ownId;

  _Screen? get _selected => _screens.where((s) => s.deviceId == _selectedId).firstOrNull;

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    _ownId = deviceId(state);
    _link = RemoteLink.create(state, RemoteRole.remote, onMessage: _onMessage)?..addListener(_onLinkChanged);
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _link?.removeListener(_onLinkChanged);
    _link?.close();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _onLinkChanged() {
    if (mounted) setState(() {});
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (msg['type'] != 'screens' || !mounted) return;
    final screens = [for (final s in (msg['screens'] as List).cast<Map>()) _Screen(s.cast<String, dynamic>())]
        .where((s) => s.deviceId != _ownId)
        .toList();
    final hadSelected = _selectedId != null;
    setState(() {
      _screens = screens;
      _received = true;
      if (_selectedId != null && _selected == null) _selectedId = null;
    });
    if (hadSelected && _selectedId == null) {
      showToast(context, 'Se ha cerrado el lector en la pantalla', icon: Icons.tv_off_rounded);
    }
  }

  void _connect(_Screen s) {
    setState(() => _selectedId = s.deviceId);
    _link?.attach(s.deviceId);
    HapticFeedback.mediumImpact();
  }

  void _send(String cmd, [Map<String, dynamic> args = const {}]) {
    final id = _selectedId;
    if (id != null) _link?.command(id, cmd, args);
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    final selected = _selected;
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selectedId = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(selected == null ? 'Modo mando' : selected.name),
          actions: [
            if (selected != null)
              TextButton.icon(
                onPressed: () => setState(() => _selectedId = null),
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Desconectar'),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: link == null
            ? const _Message(
                icon: Icons.cloud_off_rounded,
                text: 'El modo mando usa KofuSync.\nConfigúralo en Ajustes → Sincronización.',
              )
            : selected != null
            ? _Controller(screen: selected, send: _send)
            : _ScreenList(
                screens: _screens,
                loading: !_received,
                error: link.connected ? null : link.error,
                onTap: _connect,
              ),
      ),
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
  final List<_Screen> screens;
  final bool loading;
  final String? error;
  final ValueChanged<_Screen> onTap;

  const _ScreenList({required this.screens, required this.loading, required this.error, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (error != null) return _Message(icon: Icons.wifi_off_rounded, text: error!);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (screens.isEmpty) {
      return const _Message(
        icon: Icons.tv_rounded,
        text: 'Abre un cómic en el PC y aparecerá aquí.\nTodos tus dispositivos con KofuSync se ven automáticamente.',
        extra: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text('Pantallas con un libro abierto', style: TextStyle(color: Kofu.muted)),
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
                          s.name == 'PC' ? Icons.desktop_windows_rounded : Icons.tablet_mac_rounded,
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
                              s.series.isEmpty ? s.title : '${s.series} · ${s.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Kofu.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.settings_remote_rounded, color: Kofu.accent),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// El mando en sí: zonas grandes para pasar páginas, o trackpad en vertical.
class _Controller extends StatelessWidget {
  final _Screen screen;
  final void Function(String cmd, [Map<String, dynamic> args]) send;

  const _Controller({required this.screen, required this.send});

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
                  onTap: screen.hasPrev ? () => send('prevChapter') : null,
                ),
                _BarButton(icon: Icons.menu_rounded, label: 'Menú', onTap: () => send('overlay')),
                _BarButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Cap. siguiente',
                  onTap: screen.hasNext ? () => send('nextChapter') : null,
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
  final _Screen screen;

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

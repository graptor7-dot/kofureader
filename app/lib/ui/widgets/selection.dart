import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme.dart';

final random = Random();

T pickRandom<T>(List<T> items) => items[random.nextInt(items.length)];

/// Elementos seleccionados en una rejilla (mantener pulsado para empezar).
class SelectionController<T> extends ChangeNotifier {
  final Map<String, T> _selected = {};

  bool get active => _selected.isNotEmpty;
  int get count => _selected.length;
  List<T> get values => _selected.values.toList();
  bool contains(String key) => _selected.containsKey(key);

  void toggle(String key, T value) {
    if (_selected.remove(key) == null) _selected[key] = value;
    notifyListeners();
  }

  void selectAll(Map<String, T> items) {
    _selected.addAll(items);
    notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }
}

/// Barra superior que sustituye al AppBar mientras hay selección.
class SelectionBar extends StatelessWidget implements PreferredSizeWidget {
  final int count;
  final VoidCallback onClose;
  final VoidCallback? onSelectAll;
  final List<Widget> actions;

  const SelectionBar({
    super.key,
    required this.count,
    required this.onClose,
    this.onSelectAll,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Kofu.surfaceHigh,
      leading: IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
      title: Text('$count seleccionado${count == 1 ? '' : 's'}'),
      actions: [
        if (onSelectAll != null)
          IconButton(tooltip: 'Seleccionar todo', onPressed: onSelectAll, icon: const Icon(Icons.select_all)),
        ...actions,
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Botón flotante de aleatorio, con degradado.
class RandomFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final int selectedCount;
  final bool busy;

  const RandomFab({super.key, required this.onPressed, this.selectedCount = 0, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final label = selectedCount > 0 ? 'Aleatorio · $selectedCount' : 'Aleatorio';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: Kofu.accentGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Kofu.accent.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.casino_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila deslizable de chips de filtro.
class FilterRow extends StatelessWidget {
  final List<Widget> children;

  const FilterRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

void showToast(BuildContext context, String text, {IconData icon = Icons.check_circle_rounded}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Icon(icon, color: Kofu.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
}

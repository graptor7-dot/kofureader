import 'package:flutter/material.dart';

import '../../data/app_scope.dart';
import '../../theme.dart';

/// Aviso rojo de que el modo gestión está activo, con botón para salir.
class ManageBanner extends StatelessWidget {
  final String text;

  const ManageBanner({super.key, this.text = 'Modo gestión activo: entra en una serie para gestionar cada capítulo.'});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Kofu.radius),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings_rounded, color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: () => AppScope.read(context).setManageMode(false), child: const Text('Salir')),
        ],
      ),
    );
  }
}

/// Pestaña del modo gestión bajo la portada de un capítulo: 2×3 con leído, no leído,
/// favorito, lista, marcar (para agrupar) y borrar. La portada queda limpia.
class ManageBookActions extends StatelessWidget {
  final bool read;
  final bool favorite;
  final bool marked;
  final VoidCallback onRead;
  final VoidCallback onUnread;
  final VoidCallback onFavorite;
  final VoidCallback onList;
  final VoidCallback onMark;
  final VoidCallback onDelete;

  const ManageBookActions({
    super.key,
    required this.read,
    required this.favorite,
    required this.marked,
    required this.onRead,
    required this.onUnread,
    required this.onFavorite,
    required this.onList,
    required this.onMark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return _Tab(
      highlight: marked ? Kofu.accent : null,
      children: [
        [
          _TabButton(
            tooltip: 'Marcar como leído',
            icon: Icons.done_all_rounded,
            color: Kofu.read,
            active: read,
            onTap: onRead,
          ),
          _TabButton(
            tooltip: 'Marcar como no leído',
            icon: Icons.remove_done_rounded,
            color: Colors.white,
            active: !read,
            onTap: onUnread,
          ),
          _TabButton(
            tooltip: favorite ? 'Quitar de Favoritos' : 'Añadir a Favoritos',
            icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: Kofu.accent,
            active: favorite,
            onTap: onFavorite,
          ),
        ],
        [
          _TabButton(tooltip: 'Añadir a lista', icon: Icons.playlist_add_rounded, color: Kofu.gold, onTap: onList),
          _TabButton(
            tooltip: marked ? 'Desmarcar' : 'Marcar para agrupar',
            icon: marked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: Kofu.accent2,
            active: marked,
            onTap: onMark,
          ),
          _TabButton(
            tooltip: 'Borrar del servidor',
            icon: Icons.delete_forever_rounded,
            color: Colors.redAccent,
            danger: true,
            onTap: onDelete,
          ),
        ],
      ],
    );
  }
}

/// Pestaña del modo gestión bajo la portada de un autor: marcar o quitar «revisado».
class ManageReviewAction extends StatelessWidget {
  final bool reviewed;
  final VoidCallback onToggle;

  const ManageReviewAction({super.key, required this.reviewed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: reviewed ? 'Quitar revisado' : 'Marcar como revisado',
      child: Material(
        color: reviewed ? Kofu.reviewed : Kofu.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onToggle,
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: reviewed ? Kofu.reviewed : Kofu.outline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  reviewed ? Icons.verified_rounded : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: reviewed ? Colors.black : Kofu.reviewed,
                ),
                const SizedBox(width: 6),
                Text(
                  reviewed ? 'Revisado' : 'Marcar revisado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: reviewed ? Colors.black : Kofu.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final List<List<Widget>> children;
  final Color? highlight;

  const _Tab({required this.children, this.highlight});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Kofu.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ?? Kofu.outline, width: highlight != null ? 1.5 : 1),
      ),
      child: Column(
        children: [
          for (var r = 0; r < children.length; r++) ...[
            if (r > 0) const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < children[r].length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: children[r][i]),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final bool active; // estado actual: fondo de color
  final bool danger; // borrar: siempre en rojo suave
  final VoidCallback onTap;

  const _TabButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? color.withValues(alpha: 0.9)
        : danger
        ? Colors.redAccent.withValues(alpha: 0.14)
        : Kofu.surfaceHigh;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(height: 32, child: Icon(icon, size: 18, color: active ? Colors.black : color)),
        ),
      ),
    );
  }
}

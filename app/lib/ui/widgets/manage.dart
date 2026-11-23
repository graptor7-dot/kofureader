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

/// Botones rápidos sobre la portada de un capítulo en el modo gestión:
/// borrar arriba y, en el centro, 2×2 con leído, no leído, favorito y lista.
class ManageBookActions extends StatelessWidget {
  final bool read;
  final bool favorite;
  final VoidCallback onRead;
  final VoidCallback onUnread;
  final VoidCallback onFavorite;
  final VoidCallback onList;
  final VoidCallback onDelete;

  const ManageBookActions({
    super.key,
    required this.read,
    required this.favorite,
    required this.onRead,
    required this.onUnread,
    required this.onFavorite,
    required this.onList,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Botones a la medida de la portada (más grandes en pantallas anchas).
        final size = (c.maxWidth * 0.3).clamp(34.0, 54.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Kofu.radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.35)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 6,
                right: 6,
                child: _ActionButton(
                  size: size * 0.85,
                  tooltip: 'Borrar del servidor',
                  icon: Icons.delete_forever_rounded,
                  color: Colors.redAccent,
                  filled: true,
                  onTap: onDelete,
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.only(top: size * 0.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionButton(
                            size: size,
                            tooltip: 'Marcar como leído',
                            icon: Icons.done_all_rounded,
                            color: Kofu.read,
                            filled: read,
                            onTap: onRead,
                          ),
                          SizedBox(width: size * 0.25),
                          _ActionButton(
                            size: size,
                            tooltip: 'Marcar como no leído',
                            icon: Icons.remove_done_rounded,
                            color: Colors.white,
                            onTap: onUnread,
                          ),
                        ],
                      ),
                      SizedBox(height: size * 0.25),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionButton(
                            size: size,
                            tooltip: favorite ? 'Quitar de Favoritos' : 'Añadir a Favoritos',
                            icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: Kofu.accent,
                            filled: favorite,
                            onTap: onFavorite,
                          ),
                          SizedBox(width: size * 0.25),
                          _ActionButton(
                            size: size,
                            tooltip: 'Añadir a lista',
                            icon: Icons.playlist_add_rounded,
                            color: Kofu.gold,
                            onTap: onList,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final double size;
  final String tooltip;
  final IconData icon;
  final Color color;
  final bool filled; // estado activo: fondo de color
  final VoidCallback onTap;

  const _ActionButton({
    required this.size,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? color.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.7),
        shape: CircleBorder(side: BorderSide(color: color.withValues(alpha: 0.9), width: 1.5)),
        elevation: 4,
        shadowColor: Colors.black,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: size * 0.5, color: filled ? Colors.black : color),
          ),
        ),
      ),
    );
  }
}

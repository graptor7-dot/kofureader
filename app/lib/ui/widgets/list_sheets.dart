import 'package:flutter/material.dart';

import '../../data/app_scope.dart';
import '../../data/user_data.dart';
import '../../theme.dart';
import 'selection.dart';

/// Pide un nombre de lista. Devuelve null si se cancela.
Future<String?> askListName(BuildContext context, {String? initial, String title = 'Nueva lista'}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final name = controller.text.trim();
        if (name.isNotEmpty) Navigator.pop(ctx, name);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nombre de la lista'),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: submit, child: const Text('Guardar')),
        ],
      );
    },
  );
}

/// Hoja para añadir uno o varios elementos a listas.
///
/// Con un solo elemento, cada lista se marca/desmarca. Con varios, tocar
/// una lista añade todos.
Future<void> showAddToListSheet(BuildContext context, List<ItemSnapshot> items) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AddToListSheet(items: items, outerContext: context),
  );
}

class _AddToListSheet extends StatelessWidget {
  final List<ItemSnapshot> items;
  final BuildContext outerContext;

  const _AddToListSheet({required this.items, required this.outerContext});

  bool get _single => items.length == 1;

  @override
  Widget build(BuildContext context) {
    final data = AppScope.of(context).data;
    final lists = [data.favorites, ...data.customLists];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                _single ? 'Guardar "${items.first.title}"' : 'Añadir ${items.length} elementos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final list in lists) _tile(context, data, list),
                  ListTile(
                    leading: const _ListIcon(icon: Icons.add_rounded, filled: false),
                    title: const Text('Nueva lista'),
                    onTap: () async {
                      final name = await askListName(context);
                      if (name == null) return;
                      final list = data.createList(name);
                      data.addAll(list.id, items);
                      if (context.mounted) Navigator.pop(context);
                      if (outerContext.mounted) showToast(outerContext, 'Añadido a "${list.name}"');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, UserData data, UserList list) {
    final inList = _single && data.contains(list.id, items.first.ref);
    return ListTile(
      leading: _ListIcon(
        icon: list.isFavorites ? Icons.favorite_rounded : Icons.collections_bookmark_rounded,
        filled: list.isFavorites,
      ),
      title: Text(list.name),
      subtitle: Text('${data.countOf(list.id)} elementos', style: const TextStyle(color: Kofu.muted)),
      trailing: _single
          ? Icon(
              inList ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
              color: inList ? Kofu.accent : Kofu.muted,
            )
          : null,
      onTap: () {
        if (_single && inList) {
          data.removeAll(list.id, [items.first.ref]);
          return;
        }
        data.addAll(list.id, items);
        if (!_single) {
          Navigator.pop(context);
          showToast(outerContext, 'Añadido a "${list.name}"');
        }
      },
    );
  }
}

class _ListIcon extends StatelessWidget {
  final IconData icon;
  final bool filled;

  const _ListIcon({required this.icon, required this.filled});

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      gradient: filled ? Kofu.accentGradient : null,
      color: filled ? null : Kofu.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: Colors.white),
  );
}

import 'package:flutter/material.dart';

import '../../data/app_state.dart';

/// Resultado del selector cuando se elige "heredar de la biblioteca".
const inheritModeSentinel = 'inherit';

/// Muestra un selector de modo de lectura. Devuelve el modo elegido o null si se cancela.
/// Si [allowInherit] es true, elegir "Igual que la biblioteca" devuelve [inheritModeSentinel].
Future<Object?> showReadingModePickerRaw(
  BuildContext context, {
  required String title,
  required ReadingMode? current,
  bool allowInherit = false,
  String? inheritLabel,
}) {
  return showModalBottomSheet<Object>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
          if (allowInherit)
            ListTile(
              leading: Icon(current == null ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(inheritLabel ?? 'Igual que la biblioteca'),
              onTap: () => Navigator.pop(ctx, inheritModeSentinel),
            ),
          for (final m in ReadingMode.values)
            ListTile(
              leading: Icon(m == current ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(m.label),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ],
      ),
    ),
  );
}

Future<ReadingMode?> showReadingModePicker(
  BuildContext context, {
  required String title,
  required ReadingMode current,
}) async {
  final r = await showReadingModePickerRaw(context, title: title, current: current);
  return r is ReadingMode ? r : null;
}

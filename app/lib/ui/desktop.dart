import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Utilidades solo para la versión de escritorio (Windows).
bool get isDesktop => Platform.isWindows;

Future<void> initDesktop() async {
  if (isDesktop) await windowManager.ensureInitialized();
}

Future<bool> isFullScreen() async => isDesktop && await windowManager.isFullScreen();

Future<void> setFullScreen(bool value) async {
  if (isDesktop) await windowManager.setFullScreen(value);
}

Future<void> toggleFullScreen() async => setFullScreen(!await isFullScreen());

/// F11 activa o desactiva la pantalla completa en cualquier pantalla de la app.
class DesktopShortcuts extends StatelessWidget {
  final Widget child;

  const DesktopShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f11): toggleFullScreen},
      child: Focus(autofocus: true, child: child),
    );
  }
}

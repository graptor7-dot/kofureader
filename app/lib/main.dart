import 'package:flutter/material.dart';

import 'data/app_scope.dart';
import 'data/app_state.dart';
import 'data/cover_cache.dart';
import 'theme.dart';
import 'ui/desktop.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Las páginas de manga son grandes: más caché para que las precargadas no se expulsen.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 400 << 20
    ..maximumSize = 300;
  await initDesktop();
  await CoverCache.init();
  final state = AppState();
  await state.init();
  runApp(AppScope(state: state, child: const KofuApp()));
}

class KofuApp extends StatelessWidget {
  const KofuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KofuReader',
      debugShowCheckedModeBanner: false,
      theme: Kofu.theme(),
      home: const HomeScreen(),
      builder: (context, child) => DesktopShortcuts(child: child!),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/app_scope.dart';
import '../../data/updater.dart';
import '../../theme.dart';

/// Texto y acción del botón según la plataforma.
String _actionLabel(Updater u) => u.canInstallInApp ? 'Actualizar' : 'Ver versión';

Future<void> _act(BuildContext context, Updater u) async {
  if (!u.canInstallInApp && Platform.isIOS) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('KofuReader ${u.available!.version}'),
        content: const Text(
          'En el iPad la actualización se instala desde el PC: descarga KofuReader-ios.ipa '
          'de la página de la versión e instálalo con iloader (o con SideStore). '
          'Se instala encima y no pierdes nada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              u.openReleasePage();
            },
            child: const Text('Abrir página'),
          ),
        ],
      ),
    );
    return;
  }
  await u.install();
}

/// Aviso en el inicio cuando hay una versión nueva.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppScope.of(context).updater;
    final release = u.available;
    if (release == null) return const SizedBox.shrink();
    final downloading = u.progress != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Kofu.accent.withValues(alpha: 0.22), Kofu.accent2.withValues(alpha: 0.22)]),
        borderRadius: BorderRadius.circular(Kofu.radius + 4),
        border: Border.all(color: Kofu.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: Kofu.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nueva versión ${release.version}', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (downloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(value: u.progress, color: Kofu.accent),
                  )
                else
                  Text(
                    u.error ?? 'Tienes la ${u.currentVersion}',
                    style: TextStyle(fontSize: 12, color: u.error == null ? Kofu.muted : Kofu.accent),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: downloading ? null : () => _act(context, u), child: Text(_actionLabel(u))),
        ],
      ),
    );
  }
}

/// Sección "Aplicación" de Ajustes: versión instalada y búsqueda de actualizaciones.
class UpdateSettingsCard extends StatelessWidget {
  const UpdateSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppScope.of(context).updater;
    final release = u.available;
    final downloading = u.progress != null;
    final String status;
    if (u.checking) {
      status = 'Buscando actualizaciones…';
    } else if (downloading) {
      status = 'Descargando ${((u.progress ?? 0) * 100).round()} %';
    } else if (u.error != null) {
      status = u.error!;
    } else if (release != null) {
      status = 'Hay una versión nueva: ${release.version}';
    } else {
      status = 'Estás en la última versión';
    }
    return Container(
      decoration: BoxDecoration(
        color: Kofu.surface,
        borderRadius: BorderRadius.circular(Kofu.radius + 4),
        border: Border.all(color: Kofu.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(
              release != null ? Icons.system_update_rounded : Icons.verified_rounded,
              color: release != null ? Kofu.accent : Kofu.read,
            ),
            title: Text('KofuReader ${u.currentVersion}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(status, style: TextStyle(color: u.error != null ? Kofu.accent : Kofu.muted)),
          ),
          if (downloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: u.progress, color: Kofu.accent),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (release != null)
                  FilledButton.icon(
                    onPressed: downloading ? null : () => _act(context, u),
                    icon: const Icon(Icons.download_rounded),
                    label: Text('${_actionLabel(u)} a ${release.version}'),
                  ),
                OutlinedButton.icon(
                  onPressed: u.checking || downloading ? null : u.check,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Buscar actualizaciones'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_scope.dart';
import '../data/app_state.dart';
import '../data/cover_cache.dart';
import '../data/source.dart';
import '../data/sync_service.dart';
import '../komga/komga_client.dart';
import '../theme.dart';
import 'downloads_screen.dart' show formatBytes;
import 'widgets/update_widgets.dart';

/// Ajustes: servidores Komga y sincronización.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Header('Servidores Komga'),
          _Card(
            children: [
              for (final s in state.sources)
                ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: state.sourceColor(s.id).withValues(alpha: 0.18),
                    child: Icon(Icons.dns_rounded, size: 18, color: state.sourceColor(s.id)),
                  ),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    state.hasSecret(s.id) ? s.baseUrl : 'Falta la API key en este dispositivo',
                    style: TextStyle(color: state.hasSecret(s.id) ? Kofu.muted : Kofu.accent),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => SourceEditScreen(existing: s))),
                ),
              ListTile(
                leading: const CircleAvatar(
                  radius: 18,
                  backgroundColor: Kofu.surfaceHigh,
                  child: Icon(Icons.add_rounded, size: 20),
                ),
                title: const Text('Añadir servidor'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceEditScreen())),
              ),
            ],
          ),
          const _Header('Bibliotecas'),
          const _LibrariesCard(),
          const _Header('Sincronización'),
          const _SyncCard(),
          const _Header('Aplicación'),
          const UpdateSettingsCard(),
          const SizedBox(height: 12),
          const _CoverCacheCard(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
  );
}

class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Kofu.surface,
      borderRadius: BorderRadius.circular(Kofu.radius + 4),
      border: Border.all(color: Kofu.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

/// Interruptores para mostrar u ocultar cada biblioteca (se sincroniza entre dispositivos).
class _LibrariesCard extends StatefulWidget {
  const _LibrariesCard();

  @override
  State<_LibrariesCard> createState() => _LibrariesCardState();
}

class _LibrariesCardState extends State<_LibrariesCard> {
  late final Future<List<SourceLibraries>> _future = AppScope.read(context).loadAllLibraries();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<List<SourceLibraries>>(
      future: _future,
      builder: (context, snap) {
        final entries = [for (final g in snap.data ?? const <SourceLibraries>[]) ...g.libraries];
        return _Card(
          children: [
            if (!snap.hasData)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              const ListTile(
                title: Text('No hay bibliotecas disponibles', style: TextStyle(color: Kofu.muted)),
              )
            else
              for (final e in entries)
                Builder(
                  builder: (context) {
                    final disabled = state.isLibraryDisabled(e.source.id, e.library.id);
                    final private = state.isLibraryPrivate(e.source.id, e.library.id);
                    return ListTile(
                      leading: Icon(
                        disabled ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: state.sourceColor(e.source.id),
                      ),
                      title: Text(e.library.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        private ? '${e.source.name} · Privada' : e.source.name,
                        style: const TextStyle(color: Kofu.muted),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: private ? 'Quitar de privadas' : 'Marcar como privada',
                            onPressed: () => state.setLibraryPrivate(e.source.id, e.library.id, !private),
                            icon: Icon(
                              private ? Icons.lock_rounded : Icons.lock_open_rounded,
                              color: private ? Kofu.accent : Kofu.muted,
                            ),
                          ),
                          Switch(
                            value: !disabled,
                            onChanged: (visible) => state.setLibraryHidden(e.source.id, e.library.id, !visible),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text(
                'Las bibliotecas desactivadas desaparecen de todas partes (inicio, listas, favoritos, '
                'descargas y aleatorio) en todos tus dispositivos hasta que las vuelvas a activar.\n'
                'Las marcadas con 🔒 se esconden o muestran todas a la vez con el candado del inicio '
                '(solo en ese dispositivo).',
                style: TextStyle(color: Kofu.muted, fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Espacio que ocupan las portadas guardadas y botón para vaciarlas.
class _CoverCacheCard extends StatefulWidget {
  const _CoverCacheCard();

  @override
  State<_CoverCacheCard> createState() => _CoverCacheCardState();
}

class _CoverCacheCardState extends State<_CoverCacheCard> {
  late Future<int> _size = CoverCache.sizeBytes();

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: [
        FutureBuilder<int>(
          future: _size,
          builder: (context, snap) => ListTile(
            leading: const Icon(Icons.image_rounded, color: Kofu.muted),
            title: const Text('Portadas guardadas'),
            subtitle: Text(
              snap.hasData ? formatBytes(snap.data!) : 'Calculando…',
              style: const TextStyle(color: Kofu.muted),
            ),
            trailing: TextButton(
              onPressed: () async {
                await CoverCache.clear();
                setState(() => _size = CoverCache.sizeBytes());
              },
              child: const Text('Vaciar'),
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard();

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} días';
  }

  @override
  Widget build(BuildContext context) {
    final sync = AppScope.of(context).sync;
    if (!sync.configured) {
      return _Card(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_off_rounded, color: Kofu.muted),
            title: const Text('Sin configurar'),
            subtitle: const Text(
              'Conecta con tu servidor KofuSync para tener listas, favoritos y servidores en todos tus dispositivos.',
              style: TextStyle(color: Kofu.muted),
            ),
            isThreeLine: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncEditScreen())),
                icon: const Icon(Icons.cloud_sync_rounded),
                label: const Text('Configurar'),
              ),
            ),
          ),
        ],
      );
    }
    final error = sync.lastError;
    final last = sync.lastSync;
    return _Card(
      children: [
        ListTile(
          leading: sync.syncing
              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Icon(
                  error == null ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: error == null ? Kofu.read : Kofu.accent,
                ),
          title: Text(sync.url!),
          subtitle: Text(
            sync.syncing ? 'Sincronizando…' : error ?? (last == null ? 'Pendiente' : 'Sincronizado ${_ago(last)}'),
            style: TextStyle(color: error == null ? Kofu.muted : Kofu.accent),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: sync.syncing ? null : sync.syncNow,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sincronizar ahora'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncEditScreen())),
                child: const Text('Cambiar'),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('¿Desactivar sincronización?'),
                      content: const Text('Tus listas se quedan en este dispositivo y en el servidor.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desactivar')),
                      ],
                    ),
                  );
                  if (ok == true) await sync.disable();
                },
                child: const Text('Desactivar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Formulario de conexión con KofuSync.
class SyncEditScreen extends StatefulWidget {
  const SyncEditScreen({super.key});

  @override
  State<SyncEditScreen> createState() => _SyncEditScreenState();
}

class _SyncEditScreenState extends State<SyncEditScreen> {
  late final _url = TextEditingController(text: AppScope.read(context).sync.url);
  final _token = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_url.text.trim().isEmpty || _token.text.trim().isEmpty) {
      setState(() => _error = 'Rellena la URL y el token');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).sync.configure(_url.text, _token.text.trim());
      if (mounted) Navigator.pop(context);
    } on SyncException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KofuSync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'URL de KofuSync', hintText: 'http://100.x.x.x:49200'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Token (KOFUSYNC_TOKEN)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Kofu.accent)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Probar y guardar'),
          ),
        ],
      ),
    );
  }
}

/// Formulario para añadir o editar un servidor.
class SourceEditScreen extends StatefulWidget {
  final Source? existing;

  const SourceEditScreen({super.key, this.existing});

  @override
  State<SourceEditScreen> createState() => _SourceEditScreenState();
}

class _SourceEditScreenState extends State<SourceEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _url = TextEditingController(text: widget.existing?.baseUrl);
  late final _user = TextEditingController(text: widget.existing?.username);
  final _secret = TextEditingController();
  late AuthType _authType = widget.existing?.authType ?? AuthType.apiKey;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  /// Al editar un servidor que ya tiene API key en este dispositivo.
  bool get _hasStoredSecret => _isEdit && AppScope.read(context).hasSecret(widget.existing!.id);

  @override
  void dispose() {
    for (final c in [_name, _url, _user, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_url.text.trim().isEmpty || (!_hasStoredSecret && _secret.text.trim().isEmpty)) {
      setState(() => _error = 'Rellena la URL y las credenciales');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final url = Source.normalizeUrl(_url.text);
    final source = Source(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim().isEmpty ? Uri.parse(url).host : _name.text.trim(),
      baseUrl: url,
      authType: _authType,
      username: _user.text.trim(),
    );
    final state = AppScope.read(context);
    // Al editar sin escribir secreto, se conserva el guardado.
    final secret = _secret.text.trim().isEmpty ? null : _secret.text.trim();
    try {
      if (secret != null) {
        await KomgaClient(source, secret).testConnection();
      }
      await state.saveSource(source, secret);
      if (secret == null) await state.client(source.id).testConnection();
      if (mounted) Navigator.pop(context);
    } on KomgaException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar servidor?'),
        content: Text('Se quitará "${widget.existing!.name}" de la app. No se borra nada en Komga.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AppScope.read(context).removeSource(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar servidor' : 'Nuevo servidor'),
        actions: [if (_isEdit) IconButton(onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre (opcional)', hintText: 'Público, Privado…'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'URL de Komga', hintText: 'https://manga.ejemplo.com'),
          ),
          const SizedBox(height: 20),
          SegmentedButton<AuthType>(
            segments: const [
              ButtonSegment(value: AuthType.apiKey, label: Text('API key')),
              ButtonSegment(value: AuthType.basic, label: Text('Usuario y contraseña')),
            ],
            selected: {_authType},
            onSelectionChanged: (s) => setState(() => _authType = s.first),
          ),
          const SizedBox(height: 12),
          if (_authType == AuthType.basic) ...[
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Usuario (email)'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _secret,
            obscureText: true,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: _authType == AuthType.apiKey ? 'API key' : 'Contraseña',
              helperText: _hasStoredSecret ? 'Déjalo vacío para mantener la actual' : null,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Probar y guardar'),
          ),
        ],
      ),
    );
  }
}

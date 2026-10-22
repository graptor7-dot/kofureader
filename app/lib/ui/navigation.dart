import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/source.dart';
import '../data/user_data.dart';
import '../komga/models.dart';
import 'reader/reader_screen.dart';
import 'remote_screen.dart';
import 'series_screen.dart';
import 'widgets/selection.dart';

Future<void> openSeries(BuildContext context, Source source, String seriesId, {KomgaSeries? series}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SeriesScreen(source: source, seriesId: seriesId, initial: series),
    ),
  );
}

/// Abre un libro suelto: carga su serie para poder pasar al siguiente/anterior.
Future<void> openBook(BuildContext context, Source source, String bookId, {String? seriesId}) async {
  final state = AppScope.read(context);
  final client = state.client(source.id);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  List<KomgaBook> books;
  try {
    final sid = seriesId ?? (await client.book(bookId)).seriesId;
    books = await client.books(sid);
  } catch (e) {
    // Sin conexión: si el libro está descargado, leer con los descargados de su serie.
    final local = state.downloads.downloaded(source.id, bookId);
    if (local == null) {
      if (context.mounted) {
        Navigator.pop(context);
        showToast(context, '$e', icon: Icons.error_outline);
      }
      return;
    }
    books = [
      for (final b in state.downloads.ofSeries(source.id, local.seriesId))
        b.toKomgaBook(
          progress: switch (state.downloads.pendingProgress(source.id, b.bookId)) {
            final p? => KomgaReadProgress(p.page, p.completed, null),
            null => null,
          },
        ),
    ];
  }
  if (!context.mounted) return;
  Navigator.pop(context);
  final index = books.indexWhere((b) => b.id == bookId);
  await startReading(context, source, books, index < 0 ? 0 : index);
}

/// Abre el lector, o, si se está eligiendo qué leer en la tele, lo envía a la tele
/// y muestra el mando.
Future<void> startReading(BuildContext context, Source source, List<KomgaBook> books, int index) async {
  final hub = AppScope.read(context).remote;
  final tvId = hub.castTarget;
  if (tvId == null) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(source: source, books: books, initialIndex: index),
      ),
    );
    return;
  }
  try {
    await hub.castBook(tvId, source, books, index);
  } catch (e) {
    if (context.mounted) showToast(context, 'No se pudo enviar a la tele: $e', icon: Icons.error_outline);
    return;
  }
  if (!context.mounted) return;
  Navigator.popUntil(context, (r) => r.isFirst);
  await Navigator.push(context, MaterialPageRoute(builder: (_) => RemoteScreen(focus: tvId)));
}

/// Abre un elemento guardado en una lista.
Future<void> openSnapshot(BuildContext context, ItemSnapshot item) async {
  final source = AppScope.read(context).source(item.ref.sourceId);
  if (source == null) {
    showToast(context, 'Ese servidor ya no está configurado', icon: Icons.error_outline);
    return;
  }
  if (item.ref.kind == ItemKind.series) {
    await openSeries(context, source, item.ref.komgaId);
  } else {
    await openBook(context, source, item.ref.komgaId, seriesId: item.seriesId);
  }
}

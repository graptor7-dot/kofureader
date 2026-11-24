import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/chapter_groups.dart';
import '../data/chapter_label.dart';
import '../data/source.dart';
import '../data/user_data.dart';
import '../komga/chapter_kind.dart';
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
Future<void> openBook(BuildContext context, Source source, String bookId, {String? seriesId, int? page}) async {
  final state = AppScope.read(context);
  final client = state.client(source.id);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  List<KomgaBook> books;
  String? sid = seriesId;
  try {
    sid ??= (await client.book(bookId)).seriesId;
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
    sid = local.seriesId;
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
  // Seguir el apartado del libro: capítulos sin extras, o solo extras.
  classifyChapters(books, override: (b) => state.data.pref(chapterKindPrefKey(source.id, b.id)));
  final opened = books.where((b) => b.id == bookId).firstOrNull;
  // Su agrupación: dentro de una se sigue por ella en orden de número (con sus extras
  // entre capítulo y capítulo); fuera, se saltan los agrupados y se sigue el apartado.
  final groupOf = ChapterGroups(state.data, source.id, sid).byBook;
  final group = groupOf[bookId]?.id;
  if (group != null) {
    books = sortByChapterNumber(books.where((b) => groupOf[b.id]?.id == group).toList(), (b) => b.name);
  } else {
    if (opened != null) books = books.where((b) => b.isExtra == opened.isExtra).toList();
    books = books.where((b) => groupOf[b.id] == null).toList();
  }
  final index = books.indexWhere((b) => b.id == bookId);
  await startReading(context, source, books, index < 0 ? 0 : index, page: page);
}

/// Abre el lector, o, si se está eligiendo qué leer en la tele, lo envía a la tele
/// y muestra el mando.
Future<void> startReading(BuildContext context, Source source, List<KomgaBook> books, int index, {int? page}) async {
  final hub = AppScope.read(context).remote;
  final tvId = hub.castTarget;
  if (tvId == null) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(source: source, books: books, initialIndex: index, startPage: page),
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

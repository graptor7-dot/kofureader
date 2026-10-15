import 'package:flutter/material.dart';

import '../data/app_scope.dart';
import '../data/source.dart';
import '../data/user_data.dart';
import '../komga/models.dart';
import 'reader/reader_screen.dart';
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
  final client = AppScope.read(context).client(source.id);
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
    if (context.mounted) {
      Navigator.pop(context);
      showToast(context, '$e', icon: Icons.error_outline);
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.pop(context);
  final index = books.indexWhere((b) => b.id == bookId);
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ReaderScreen(source: source, books: books, initialIndex: index < 0 ? 0 : index),
    ),
  );
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

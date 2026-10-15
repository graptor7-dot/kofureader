import '../komga/models.dart';
import 'user_data.dart';

/// Conversión de objetos de Komga a referencias guardables en listas.
extension SeriesSnapshot on KomgaSeries {
  ItemSnapshot snapshot(String sourceId) =>
      ItemSnapshot(ref: ItemRef(sourceId, ItemKind.series, id), title: title, libraryId: libraryId);
}

extension BookSnapshot on KomgaBook {
  ItemSnapshot snapshot(String sourceId) => ItemSnapshot(
    ref: ItemRef(sourceId, ItemKind.book, id),
    title: title,
    libraryId: libraryId,
    seriesId: seriesId,
    seriesTitle: seriesTitle,
  );
}

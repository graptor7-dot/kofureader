/// Modelos mínimos de la API de Komga (solo los campos que usa la app).
library;

class KomgaPage<T> {
  final List<T> content;
  final int totalElements;
  final bool last;

  KomgaPage(this.content, this.totalElements, this.last);

  factory KomgaPage.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    return KomgaPage(
      (json['content'] as List).map((e) => parse(e as Map<String, dynamic>)).toList(),
      json['totalElements'] as int? ?? 0,
      json['last'] as bool? ?? true,
    );
  }
}

class KomgaLibrary {
  final String id;
  final String name;

  KomgaLibrary(this.id, this.name);

  factory KomgaLibrary.fromJson(Map<String, dynamic> j) => KomgaLibrary(j['id'] as String, j['name'] as String);
}

class KomgaSeries {
  final String id;
  final String libraryId;
  final String title;
  final int booksCount;
  final int booksReadCount;
  final int booksInProgressCount;

  KomgaSeries({
    required this.id,
    required this.libraryId,
    required this.title,
    required this.booksCount,
    required this.booksReadCount,
    required this.booksInProgressCount,
  });

  int get booksUnreadCount => booksCount - booksReadCount;

  factory KomgaSeries.fromJson(Map<String, dynamic> j) {
    final meta = j['metadata'] as Map<String, dynamic>? ?? const {};
    return KomgaSeries(
      id: j['id'] as String,
      libraryId: j['libraryId'] as String,
      title: (meta['title'] as String?) ?? j['name'] as String,
      booksCount: j['booksCount'] as int? ?? 0,
      booksReadCount: j['booksReadCount'] as int? ?? 0,
      booksInProgressCount: j['booksInProgressCount'] as int? ?? 0,
    );
  }
}

class KomgaReadProgress {
  final int page;
  final bool completed;
  final DateTime? readDate;

  KomgaReadProgress(this.page, this.completed, this.readDate);
}

/// Filtro de estado de lectura (valores de la API de Komga).
enum ReadStatus {
  unread('UNREAD', 'Sin leer'),
  inProgress('IN_PROGRESS', 'En curso'),
  read('READ', 'Leídos');

  final String api;
  final String label;
  const ReadStatus(this.api, this.label);
}

/// Orden de las series (campo de la API de Komga).
enum SeriesSort {
  title('metadata.titleSort,asc', 'Título'),
  added('createdDate,desc', 'Añadidas recientemente'),
  updated('lastModified,desc', 'Actualizadas recientemente');

  final String api;
  final String label;
  const SeriesSort(this.api, this.label);
}

class KomgaBook {
  final String id;
  final String seriesId;
  final String seriesTitle;
  final String libraryId;
  final String title;
  final String number;
  final int pagesCount;
  final KomgaReadProgress? readProgress;

  KomgaBook({
    required this.id,
    required this.seriesId,
    required this.seriesTitle,
    required this.libraryId,
    required this.title,
    required this.number,
    required this.pagesCount,
    required this.readProgress,
  });

  bool get isRead => readProgress?.completed ?? false;
  bool get inProgress => readProgress != null && !readProgress!.completed;
  DateTime? get readDate => readProgress?.readDate;

  ReadStatus get status => isRead
      ? ReadStatus.read
      : inProgress
      ? ReadStatus.inProgress
      : ReadStatus.unread;

  /// Fracción leída (0..1) para barras de progreso.
  double get progressFraction {
    final rp = readProgress;
    if (rp == null || pagesCount == 0) return 0;
    if (rp.completed) return 1;
    return rp.page / pagesCount;
  }

  factory KomgaBook.fromJson(Map<String, dynamic> j) {
    final meta = j['metadata'] as Map<String, dynamic>? ?? const {};
    final media = j['media'] as Map<String, dynamic>? ?? const {};
    final rp = j['readProgress'] as Map<String, dynamic>?;
    return KomgaBook(
      id: j['id'] as String,
      seriesId: j['seriesId'] as String,
      seriesTitle: j['seriesTitle'] as String? ?? '',
      libraryId: j['libraryId'] as String,
      title: (meta['title'] as String?) ?? j['name'] as String,
      number: (meta['number'] as String?) ?? '${j['number'] ?? ''}',
      pagesCount: media['pagesCount'] as int? ?? 0,
      readProgress: rp == null
          ? null
          : KomgaReadProgress(
              rp['page'] as int? ?? 1,
              rp['completed'] as bool? ?? false,
              DateTime.tryParse(rp['readDate'] as String? ?? ''),
            ),
    );
  }
}

class KomgaPageInfo {
  final int number; // empieza en 1
  final int? width;
  final int? height;

  KomgaPageInfo(this.number, this.width, this.height);

  double? get aspectRatio => (width != null && height != null && width! > 0 && height! > 0) ? width! / height! : null;

  factory KomgaPageInfo.fromJson(Map<String, dynamic> j) =>
      KomgaPageInfo(j['number'] as int, j['width'] as int?, j['height'] as int?);
}

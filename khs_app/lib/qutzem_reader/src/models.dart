enum BookFormat { pdf, epub, fb2 }

extension BookFormatExt on BookFormat {
  String get extension {
    switch (this) {
      case BookFormat.pdf:
        return 'pdf';
      case BookFormat.epub:
        return 'epub';
      case BookFormat.fb2:
        return 'fb2';
    }
  }

  String get label {
    switch (this) {
      case BookFormat.pdf:
        return 'PDF';
      case BookFormat.epub:
        return 'EPUB';
      case BookFormat.fb2:
        return 'FB2';
    }
  }

  static BookFormat? fromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return BookFormat.pdf;
    if (lower.endsWith('.epub')) return BookFormat.epub;
    if (lower.endsWith('.fb2') || lower.endsWith('.fb2.zip')) {
      return BookFormat.fb2;
    }
    return null;
  }
}

class Book {
  final String id;
  String title;
  String author;
  BookFormat format;
  String fileName;
  int sizeBytes;
  String? coverPath;
  DateTime addedAt;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.fileName,
    required this.sizeBytes,
    this.coverPath,
    required this.addedAt,
  });

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Без названия',
        author: json['author'] as String? ?? '',
        format: BookFormat.values.firstWhere(
          (e) => e.name == json['format'],
          orElse: () => BookFormat.epub,
        ),
        fileName: json['fileName'] as String,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        coverPath: json['coverPath'] as String?,
        addedAt: DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format.name,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'coverPath': coverPath,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };
}

class Highlight {
  final String id;
  final int chapter;
  final int start;
  final int end;
  final String text;
  final int colorIndex;
  final String? note;
  final String? chapterTitle;
  final DateTime createdAt;

  Highlight({
    required this.id,
    required this.chapter,
    required this.start,
    required this.end,
    required this.text,
    this.colorIndex = 0,
    this.note,
    this.chapterTitle,
    required this.createdAt,
  });

  factory Highlight.fromJson(Map<String, dynamic> json) => Highlight(
        id: json['id'] as String,
        chapter: json['chapter'] as int? ?? 0,
        start: json['start'] as int,
        end: json['end'] as int,
        text: json['text'] as String? ?? '',
        colorIndex: json['colorIndex'] as int? ?? 0,
        note: json['note'] as String?,
        chapterTitle: json['chapterTitle'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chapter': chapter,
        'start': start,
        'end': end,
        'text': text,
        'colorIndex': colorIndex,
        'note': note,
        'chapterTitle': chapterTitle,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}

class Bookmark {
  final String id;
  final int chapter;
  final int offset;
  final String label;
  final DateTime createdAt;

  Bookmark({
    required this.id,
    required this.chapter,
    required this.offset,
    required this.label,
    required this.createdAt,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: json['id'] as String,
        chapter: json['chapter'] as int? ?? 0,
        offset: json['offset'] as int? ?? 0,
        label: json['label'] as String? ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chapter': chapter,
        'offset': offset,
        'label': label,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
}

class ReadingState {
  int chapter;
  int charOffset;
  int chapterCount;

  ReadingState({
    this.chapter = 0,
    this.charOffset = 0,
    this.chapterCount = 0,
  });

  double get progress {
    if (chapterCount <= 1) return charOffset > 0 ? 1.0 : 0.0;
    final step = 1.0 / (chapterCount - 1);
    return (chapter * step).clamp(0.0, 1.0);
  }

  factory ReadingState.fromJson(Map<String, dynamic>? json) => json == null
      ? ReadingState()
      : ReadingState(
          chapter: json['chapter'] as int? ?? 0,
          charOffset: json['charOffset'] as int? ?? 0,
          chapterCount: json['chapterCount'] as int? ?? 0,
        );

  Map<String, dynamic> toJson() => {
        'chapter': chapter,
        'charOffset': charOffset,
        'chapterCount': chapterCount,
      };
}

class BookData {
  final Book book;
  ReadingState reading;
  List<Highlight> highlights;
  List<Bookmark> bookmarks;

  BookData({
    required this.book,
    required this.reading,
    required this.highlights,
    this.bookmarks = const [],
  });

  factory BookData.fromJson(Map<String, dynamic> json, Book book) => BookData(
        book: book,
        reading: ReadingState.fromJson(json['reading'] as Map<String, dynamic>?),
        highlights: (json['highlights'] as List<dynamic>? ?? [])
            .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
            .toList(),
        bookmarks: (json['bookmarks'] as List<dynamic>? ?? [])
            .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'reading': reading.toJson(),
        'highlights': highlights.map((h) => h.toJson()).toList(),
        'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
      };
}
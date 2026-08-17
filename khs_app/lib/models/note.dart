class Note {
  final int? id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// День, к которому относится заметка (ежедневная заметка).
  /// `null` — отдельная заметка, не привязанная к дате.
  final DateTime? date;

  /// Стабильный ключ для синхронизации между устройствами.
  final String? clientKey;

  /// Мягкое удаление (см. Task.deleted).
  final bool deleted;

  const Note({
    this.id,
    required this.title,
    this.content = '',
    required this.createdAt,
    required this.updatedAt,
    this.date,
    this.clientKey,
    this.deleted = false,
  });

  String get snippet {
    final lines = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    return lines.isEmpty ? '' : lines.first.trim();
  }

  Note copyWith({
    int? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? date,
    String? clientKey,
    bool? deleted,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      date: date ?? this.date,
      clientKey: clientKey ?? this.clientKey,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'note_date': date?.millisecondsSinceEpoch,
      'client_key': clientKey,
      'deleted': deleted ? 1 : 0,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      date: map['note_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['note_date'] as int),
      clientKey: map['client_key'] as String?,
      deleted: (map['deleted'] as int? ?? 0) == 1,
    );
  }
}

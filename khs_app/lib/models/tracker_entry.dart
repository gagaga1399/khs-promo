/// Тип значения свойства заметки — для показа и подсказки будущим трекерам.
enum TrackerPropertyKind {
  boolean,
  number,
  date,
  list,
  text;

  /// Человекочитаемая подпись типа.
  String label(bool russian) => switch (this) {
    TrackerPropertyKind.boolean => russian ? 'да/нет' : 'yes/no',
    TrackerPropertyKind.number => russian ? 'число' : 'number',
    TrackerPropertyKind.date => russian ? 'дата' : 'date',
    TrackerPropertyKind.list => russian ? 'список' : 'list',
    TrackerPropertyKind.text => russian ? 'текст' : 'text',
  };
}

/// Заметка с датой, прочитанная из хранилища Obsidian: дата плюс свойства
/// из frontmatter (или inline `[ключ:: значение]`).
///
/// Трекеры будут строиться поверх этих записей: одно свойство (например,
/// `тренировка` или `самоощущение`) изо дня в день даёт серию значений.
class TrackerEntry {
  /// Дата, к которой относится заметка.
  final DateTime date;

  /// Заголовок — имя файла без расширения (обычно `YYYY-MM-DD`).
  final String title;

  /// Полный путь к файлу в хранилище.
  final String path;

  /// Свойства заметки: `ключ → значение` (bool, num, String, List).
  /// Служебное `date` сюда не попадает — дата живёт в [date].
  final Map<String, Object?> properties;

  /// Тело заметки без frontmatter. Используется дашбордом для подсчёта
  /// слов и выполненных задач.
  final String body;

  const TrackerEntry({
    required this.date,
    required this.title,
    required this.path,
    required this.properties,
    this.body = '',
  });

  @override
  String toString() =>
      'TrackerEntry(${date.toIso8601String()}, ${properties.length} props)';
}

/// Свойство, встречающееся в заметках с датами, — кандидат в трекер.
class TrackerProperty {
  /// Имя свойства так, как оно записано во frontmatter.
  final String name;

  /// Тип значения (по большинству непустых значений).
  final TrackerPropertyKind kind;

  /// Сколько заметок содержат непустое значение свойства.
  final int filled;

  /// Всего заметок с датой, среди которых искали.
  final int total;

  /// Несколько примеров значений для предпросмотра.
  final List<String> samples;

  const TrackerProperty({
    required this.name,
    required this.kind,
    required this.filled,
    required this.total,
    this.samples = const [],
  });

  double get ratio => total == 0 ? 0 : filled / total;

  @override
  String toString() => 'TrackerProperty($name, $kind, $filled/$total)';
}

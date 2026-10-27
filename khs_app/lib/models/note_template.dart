import 'package:flutter/foundation.dart';

/// Одно свойство (frontmatter) шаблона заметки.
@immutable
class NotePropertySpec {
  const NotePropertySpec({required this.key, this.value});

  final String key;
  final Object? value;

  Map<String, Object?> toJson() => {'key': key, 'value': value};

  factory NotePropertySpec.fromJson(Map<String, Object?> json) =>
      NotePropertySpec(
        key: (json['key'] as String?) ?? '',
        value: json['value'],
      );
}

/// Пользовательский шаблон заметки: имя, тело и свойства по умолчанию.
///
/// В теле поддерживаются подстановки `{{title}}` (название заметки) и
/// `{{date}}` (сегодняшняя дата в формате `YYYY-MM-DD`).
class NoteTemplate {
  NoteTemplate({
    required this.id,
    required this.name,
    this.body = '',
    List<NotePropertySpec> properties = const [],
  }) : properties = List<NotePropertySpec>.of(properties);

  final String id;
  String name;
  String body;
  List<NotePropertySpec> properties;

  String bodyFor(String title, DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final iso = '${date.year}-$month-$day';
    return body.replaceAll('{{title}}', title).replaceAll('{{date}}', iso);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'body': body,
    'properties': properties.map((p) => p.toJson()).toList(),
  };

  factory NoteTemplate.fromJson(Map<String, Object?> json) => NoteTemplate(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    body: (json['body'] as String?) ?? '',
    properties: [
      for (final item in (json['properties'] as List? ?? const []))
        if (item is Map) NotePropertySpec.fromJson(item.cast<String, Object?>()),
    ],
  );
}

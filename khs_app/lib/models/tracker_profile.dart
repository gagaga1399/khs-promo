import 'tracker_entry.dart';

/// Трекер, добавленный пользователем вручную. Может не иметь данных в
/// хранилище — тогда карточка покажет пустой график, но трекер будет виден.
class CustomTracker {
  const CustomTracker({required this.name, required this.kind});

  final String name;
  final TrackerPropertyKind kind;

  Map<String, Object?> toJson() => {'name': name, 'kind': kind.name};

  factory CustomTracker.fromJson(Map<String, dynamic> json) => CustomTracker(
    name: (json['name'] as String?) ?? '',
    kind: TrackerPropertyKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => TrackerPropertyKind.boolean,
    ),
  );
}

/// Профиль человека: набор настроек трекеров поверх общего хранилища.
///
/// Трекеры в приложении выводятся из свойств заметок Obsidian, поэтому профиль
/// хранит не сами данные, а выбор: какие свойства показывать, какие скрыть и
/// какие трекеры добавлены вручную.
class TrackerProfile {
  TrackerProfile({
    required this.id,
    required this.name,
    Set<String>? hidden,
    List<CustomTracker>? custom,
  }) : hidden = hidden ?? <String>{},
       custom = custom ?? <CustomTracker>[];

  final String id;
  String name;

  /// Имена свойств, скрытых из списка трекеров в этом профиле.
  final Set<String> hidden;

  /// Трекеры, добавленные пользователем вручную.
  final List<CustomTracker> custom;

  /// Все имена настроенных вручную трекеров (для проверки дублей).
  bool hasCustom(String trackerName) =>
      custom.any((c) => c.name == trackerName);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'hidden': hidden.toList(),
    'custom': custom.map((c) => c.toJson()).toList(),
  };

  factory TrackerProfile.fromJson(Map<String, dynamic> json) => TrackerProfile(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    hidden: {
      for (final item in (json['hidden'] as List? ?? const [])) '$item',
    },
    custom: [
      for (final item in (json['custom'] as List? ?? const []))
        if (item is Map) CustomTracker.fromJson(item.cast<String, dynamic>()),
    ],
  );
}

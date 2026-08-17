import 'package:intl/intl.dart';

class Task {
  final int? id;
  final String title;
  final String? notes;
  final DateTime? dueAt;
  final int priority; // 0 low, 1 normal, 2 high
  final bool completed;
  final String recurrence; // '', 'daily', 'weekly', 'monthly'
  final DateTime? reminderAt;
  final String? category; // группа (General, Meetings, Trip…)
  final DateTime createdAt;
  final DateTime? completedAt;

  /// Показывать push-уведомление в момент напоминания (пользователь может
  /// отключить на задаче — «без СМС»).
  final bool notify;

  /// Стабильный ключ для синхронизации между устройствами.
  final String? clientKey;

  /// Мягкое удаление: запись остаётся в базе, но скрыта, пока другой
  /// устройство не узнает про удаление через синхронизацию.
  final bool deleted;

  /// Время последнего изменения — для «последний пишет первым» при слиянии.
  final DateTime? updatedAt;

  const Task({
    this.id,
    required this.title,
    this.notes,
    this.dueAt,
    this.priority = 1,
    this.completed = false,
    this.recurrence = '',
    this.reminderAt,
    this.category,
    required this.createdAt,
    this.completedAt,
    this.clientKey,
    this.deleted = false,
    this.updatedAt,
    this.notify = true,
  });

  DateTime get effectiveUpdatedAt => updatedAt ?? createdAt;

  bool get isRecurring => recurrence.isNotEmpty;

  DateTime? get dueDate =>
      dueAt == null ? null : DateTime(dueAt!.year, dueAt!.month, dueAt!.day);

  String? get dueTime {
    if (dueAt == null) return null;
    return DateFormat('HH:mm').format(dueAt!);
  }

  Task copyWith({
    int? id,
    String? title,
    String? notes,
    DateTime? dueAt,
    bool clearDueAt = false,
    int? priority,
    bool? completed,
    String? recurrence,
    DateTime? reminderAt,
    bool clearReminder = false,
    String? category,
    bool clearCategory = false,
    DateTime? createdAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? clientKey,
    bool? deleted,
    DateTime? updatedAt,
    bool? notify,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      recurrence: recurrence ?? this.recurrence,
      reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
      category: clearCategory ? null : (category ?? this.category),
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      clientKey: clientKey ?? this.clientKey,
      deleted: deleted ?? this.deleted,
      updatedAt: updatedAt ?? this.updatedAt,
      notify: notify ?? this.notify,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'notes': notes,
      'due_at': dueAt?.millisecondsSinceEpoch,
      'priority': priority,
      'completed': completed ? 1 : 0,
      'recurrence': recurrence,
      'reminder_at': reminderAt?.millisecondsSinceEpoch,
      'category': category,
      'created_at': createdAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'client_key': clientKey,
      'deleted': deleted ? 1 : 0,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'notify': notify ? 1 : 0,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as int?,
      title: map['title'] as String,
      notes: map['notes'] as String?,
      dueAt: map['due_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['due_at'] as int),
      priority: map['priority'] as int? ?? 1,
      completed: (map['completed'] as int? ?? 0) == 1,
      recurrence: map['recurrence'] as String? ?? '',
      reminderAt: map['reminder_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['reminder_at'] as int),
      category: map['category'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int),
      clientKey: map['client_key'] as String?,
      deleted: (map['deleted'] as int? ?? 0) == 1,
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      notify: (map['notify'] as int? ?? 1) == 1,
    );
  }

  Task nextOccurrence() {
    final due = dueAt;
    if (due == null || !isRecurring) return this;
    DateTime next;
    switch (recurrence) {
      case 'daily':
        next = due.add(const Duration(days: 1));
        break;
      case 'weekly':
        next = due.add(const Duration(days: 7));
        break;
      case 'monthly':
        next = DateTime(
          due.year,
          due.month + 1,
          due.day,
          due.hour,
          due.minute,
          due.second,
        );
        break;
      default:
        return this;
    }
    final reminder = reminderAt;
    return Task(
      id: null,
      title: title,
      notes: notes,
      dueAt: next,
      priority: priority,
      completed: false,
      recurrence: recurrence,
      reminderAt: reminder == null
          ? null
          : next.subtract(due.difference(reminder)),
      category: category,
      createdAt: DateTime.now(),
      clientKey: null,
      deleted: false,
      notify: notify,
    );
  }

  Task withCompleted(bool value) {
    return copyWith(
      completed: value,
      completedAt: value ? DateTime.now() : null,
      clearCompletedAt: !value,
    );
  }
}

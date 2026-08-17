import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/app_strings.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../services/obsidian_service.dart';
import '../services/sync_client.dart';
import '../services/sync_server.dart';
import '../services/task_database.dart';
import '../services/update_checker.dart';
import '../ui/app_theme.dart';
import '../utils/task_parser.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  static const defaultVaultPath = '';
  static const defaultSyncPort = 4680;
  static const noteReminderNotificationId = 777001;

  static const _installChannel = MethodChannel('khs/install');
  static const _vaultChannel = MethodChannel('khs/vault');
  static const _backgroundChannel = MethodChannel('khs/background');

  // ---------- Типы элементов статистики (для настройки «что показывать») ----------
  static const barGroups = 'groups'; // столбики по группам
  static const barPriorities = 'priorities'; // столбики по приоритетам
  static const barPeriods = 'periods'; // кольца «сегодня» / «неделя»
  static const barGoal = 'goal'; // дневная цель и серия
  static const barOverdue = 'overdue'; // сводка по просроченным
  static const barSidebar = 'sidebar'; // линейные бары в сайдбаре
  static const barWeek = 'week'; // график за неделю
  static const barMonth = 'month'; // график за месяц
  static const barMonthCompare = 'monthCompare'; // сравнение месяцев

  static const List<String> allBars = [
    barGoal,
    barPriorities,
    barWeek,
    barMonth,
    barMonthCompare,
    barOverdue,
    barSidebar,
  ];

  final TaskDatabase db = TaskDatabase();
  final NotificationService notifications = NotificationService();
  final TaskParser parser = TaskParser();

  SharedPreferences? _prefs;
  String _locale = 'ru';
  List<Task> _tasks = [];
  List<Note> _notes = [];
  List<Note> _deletedNotes = [];
  List<String> _groups = [];
  Color _accentColor = AppTheme.defaultAccent;
  DateTime _selectedDate = _today();
  bool ready = false;
  String _mode = 'home'; // 'home' | 'design'
  int? _selectedTaskId;
  bool _notificationsEnabled = true;
  bool _isDarkTheme = true;

  bool _syncEnabled = false;
  String _syncAddress = '';
  String _syncToken = '';
  bool _syncServerEnabled = false;
  int _syncPort = defaultSyncPort;
  DateTime? _lastSyncTime;
  String _lastSyncStatus = ''; // '' | 'ok' | 'offline' | 'error'
  bool _syncing = false;
  SyncServer? _syncServer;
  Timer? _syncTimer;
  List<String> _localAddresses = const [];

  bool _noteReminderEnabled = false;
  int _noteReminderMinutes = 20 * 60; // 20:00

  // ---------- Прогресс ----------
  int _dailyGoal = 5; // дневная цель — задач в день
  Set<String> _progressBars = {
    barGoal,
    barPriorities,
    barWeek,
    barMonth,
    barMonthCompare,
    barOverdue,
    barSidebar,
  };

  late ObsidianService _obsidian;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String get locale => _locale;
  List<Task> get tasks => List.unmodifiable(_tasks);
  List<Note> get notes => List.unmodifiable(_notes);

  /// Заметки в корзине (мягко удалённые).
  List<Note> get deletedNotes => List.unmodifiable(_deletedNotes);
  DateTime get selectedDate => _selectedDate;
  bool get isDarkTheme => _isDarkTheme;
  Color get accentColor => _accentColor;
  AppStrings get strings => AppStrings(_locale);

  bool get isPc => Platform.isWindows;
  bool get syncEnabled => _syncEnabled;
  String get syncAddress => _syncAddress;
  String get syncToken => _syncToken;
  bool get syncServerEnabled => _syncServerEnabled;
  int get syncPort => _syncPort;
  DateTime? get lastSyncTime => _lastSyncTime;
  String get lastSyncStatus => _lastSyncStatus;
  bool get syncing => _syncing;
  bool get syncServerRunning => _syncServer?.isRunning ?? false;
  List<String> get localAddresses => List.unmodifiable(_localAddresses);

  bool get noteReminderEnabled => _noteReminderEnabled;
  int get noteReminderMinutes => _noteReminderMinutes;

  int get dailyGoal => _dailyGoal;
  Set<String> get progressBars => Set.unmodifiable(_progressBars);

  bool barEnabled(String id) => _progressBars.contains(id);

  void setBarEnabled(String id, bool value) {
    if (value) {
      _progressBars.add(id);
    } else {
      _progressBars.remove(id);
    }
    _prefs?.setStringList('progress_bars', _progressBars.toList());
    notifyListeners();
  }

  String get mode => _mode;
  bool get isDesignMode => _mode == 'design';
  void setMode(String mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  Task? get selectedTask {
    final id = _selectedTaskId;
    if (id == null) return null;
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void selectTask(Task task) {
    _selectedTaskId = task.id;
    notifyListeners();
  }

  Future<bool> attachTagToSelected(String tag) async {
    final trimmed = tag.trim();
    final t = selectedTask;
    if (t == null || trimmed.isEmpty) return false;
    await createGroup(trimmed);
    final updated = t.copyWith(category: trimmed);
    await db.updateTask(updated);
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i != -1) _tasks[i] = updated;
    notifyListeners();
    return true;
  }

  String? _categoryFilter;
  String? get categoryFilter => _categoryFilter;
  void setCategoryFilter(String? category) {
    _categoryFilter = category;
    notifyListeners();
  }

  int? _priorityFilter;
  int? get priorityFilter => _priorityFilter;
  void setPriorityFilter(int? priority) {
    _priorityFilter = priority;
    notifyListeners();
  }

  /// Список задач для центральной панели: по выбранной группе или по дню,
  /// плюс фильтр по приоритету (null — все).
  /// Выполненные не скрываются, а остаются внизу с пометкой.
  List<Task> get filteredTasks {
    final c = _categoryFilter;
    final p = _priorityFilter;
    final List<Task> result;
    if (c == null) {
      result = tasksForSelectedDate;
    } else {
      result = _tasks.where((t) => t.category == c).toList()
        ..sort(_taskSorter);
    }
    if (p == null) return result;
    return result.where((t) => t.priority == p).toList();
  }

  /// Сортировка: сначала невыполненные (по приоритету и сроку),
  /// затем выполненные.
  static int _taskSorter(Task a, Task b) {
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    if (a.priority != b.priority) return b.priority - a.priority;
    return (a.dueAt?.millisecondsSinceEpoch ?? 0).compareTo(
      b.dueAt?.millisecondsSinceEpoch ?? 0,
    );
  }

  ObsidianService get obsidian => _obsidian;

  /// Группы из настроек + группы, встречающиеся в задачах.
  List<String> get groups {
    final result = <String>[..._groups];
    for (final t in _tasks) {
      final c = t.category;
      if (c != null && c.trim().isNotEmpty && !result.contains(c)) {
        result.add(c);
      }
    }
    return result;
  }

  int countFor(String category) =>
      _tasks.where((t) => !t.completed && t.category == category).length;

  int progressPercent(String? category) {
    final all = category == null
        ? _tasks
        : _tasks.where((t) => t.category == category).toList();
    if (all.isEmpty) return 0;
    final done = all.where((t) => t.completed).length;
    return (done * 100 / all.length).round();
  }

  /// Прогресс по весу задачи (priority: 0 low, 1 normal, 2 high).
  int progressPercentForPriority(int priority, {String? category}) {
    final all = _tasks.where(
      (t) =>
          t.priority == priority &&
          (category == null || t.category == category),
    );
    if (all.isEmpty) return 0;
    final done = all.where((t) => t.completed).length;
    return (done * 100 / all.length).round();
  }

  /// Сколько задач было выполнено за указанный день.
  int doneCountOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _tasks.where(
      (t) =>
          t.completed &&
          t.completedAt != null &&
          !t.completedAt!.isBefore(start) &&
          t.completedAt!.isBefore(end),
    ).length;
  }

  /// Выполненные задачи за последние [days] дней (от старого к сегодняшнему).
  List<int> doneCountsLast(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(days, (i) {
      final day = today.subtract(Duration(days: days - 1 - i));
      return doneCountOn(day);
    });
  }

  /// Выполненные задачи по дням за указанный месяц (1..31).
  List<int> doneCountsMonth(int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return List.generate(daysInMonth, (i) {
      final day = DateTime(year, month, i + 1);
      return doneCountOn(day);
    });
  }

  /// Суммарно выполнено за месяц.
  int doneCountMonth(int year, int month) {
    return doneCountsMonth(year, month).fold(0, (a, b) => a + b);
  }

  int get doneToday => doneCountOn(DateTime.now());

  /// Процент выполнения дневной цели (0..100, без потолка не больше 100).
  int get dailyGoalPercent => _dailyGoal <= 0
      ? 0
      : (doneToday * 100 / _dailyGoal).round().clamp(0, 100);

  /// Дни подряд, когда цель была выполнена. Если сегодня цель ещё не
  /// выполнена, серия считается от вчера, чтобы текущий день не сбрасывал её
  /// до завершения.
  int get streakDays {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (doneCountOn(day) < _dailyGoal) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (doneCountOn(day) >= _dailyGoal) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Просроченные задачи (не выполнены, срок прошёл).
  int overdueCount(String? category) {
    final now = DateTime.now();
    return _tasks.where(
      (t) =>
          !t.completed &&
          t.dueAt != null &&
          t.dueAt!.isBefore(now) &&
          (category == null || t.category == category),
    ).length;
  }

  /// Прогресс по задачам со сроком сегодня.
  int progressPercentDueToday() {
    final today = _today();
    final all = _tasks.where(
      (t) =>
          t.dueAt != null &&
          t.dueAt!.year == today.year &&
          t.dueAt!.month == today.month &&
          t.dueAt!.day == today.day,
    );
    if (all.isEmpty) return 0;
    final done = all.where((t) => t.completed).length;
    return (done * 100 / all.length).round();
  }

  /// Прогресс по задачам со сроком в ближайшие 7 дней (включая сегодня).
  int progressPercentDueWeek() {
    final today = _today();
    final weekEnd = today.add(const Duration(days: 7));
    final all = _tasks.where(
      (t) =>
          t.dueAt != null &&
          !t.dueAt!.isBefore(today) &&
          t.dueAt!.isBefore(weekEnd),
    );
    if (all.isEmpty) return 0;
    final done = all.where((t) => t.completed).length;
    return (done * 100 / all.length).round();
  }

  Task? get nextReminder {
    final now = DateTime.now();
    final reminders = _tasks.where(
      (t) => !t.completed && t.reminderAt != null && t.reminderAt!.isAfter(now),
    );
    if (reminders.isEmpty) return null;
    return reminders.reduce(
      (a, b) => a.reminderAt!.isBefore(b.reminderAt!) ? a : b,
    );
  }

  List<Task> upcomingEvents(int limit) {
    final now = DateTime.now();
    final events = _tasks.where((t) => !t.completed && t.dueAt != null);
    final sorted = events.toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final future = sorted.where(
      (t) => t.dueAt!.isAfter(now.subtract(const Duration(days: 1))),
    );
    return future.take(limit).toList();
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _locale = _prefs?.getString('locale') ?? 'ru';
    _accentColor = Color(
      _prefs?.getInt('accent_color') ?? AppTheme.defaultAccent.toARGB32(),
    );
    _groups = _prefs?.getStringList('groups') ?? [];
    _notificationsEnabled = _prefs?.getBool('notifications_enabled') ?? true;
    _isDarkTheme = _prefs?.getBool('dark_theme') ?? true;
    _syncEnabled = _prefs?.getBool('sync_enabled') ?? false;
    _syncAddress = _cleanSyncAddress(_prefs?.getString('sync_address') ?? '');
    _syncToken = _prefs?.getString('sync_token') ?? '';
    _syncServerEnabled = _prefs?.getBool('sync_server_enabled') ?? false;
    _syncPort = _prefs?.getInt('sync_port') ?? defaultSyncPort;
    _noteReminderEnabled = _prefs?.getBool('note_reminder_enabled') ?? false;
    _noteReminderMinutes = _prefs?.getInt('note_reminder_minutes') ?? 20 * 60;
    _dailyGoal = _prefs?.getInt('daily_goal') ?? 5;
    final savedBars = _prefs?.getStringList('progress_bars');
    if (savedBars != null && savedBars.isNotEmpty) {
      _progressBars = savedBars.toSet();
    }
    _savedVaultPaths = _prefs?.getStringList('saved_vault_paths') ?? [];
    final vaultPath =
        _prefs?.getString('obsidian_vault_path') ?? defaultVaultPath;
    _obsidian = ObsidianService(vaultPath);
    await notifications.init();
    await notifications.requestPermissions();
    _tasks = await db.getTasks();
    _notes = await db.getNotes();
    _deletedNotes = await db.getDeletedNotes();
    // Перепланируем пуши для активных задач: если будильники пропали
    // (например, после перезагрузки или переустановки), восстановим их.
    for (final t in _tasks) {
      if (t.id != null && !t.completed) {
        await _scheduleNotification(t);
      }
    }
    ready = true;
    notifyListeners();
    await _ensureDailyOccurrences();
    try {
      await syncWithObsidian();
    } catch (_) {}
    if (isPc && _syncServerEnabled) {
      await _startSyncServer();
    } else if (!isPc && _syncEnabled && _syncAddress.trim().isNotEmpty) {
      _startAutoSync();
    }
    if (!isPc) {
      WidgetsBinding.instance.addObserver(this);
      _scheduleNoteReminder();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensureDailyOccurrences();
      _maybeSync();
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    if (!isPc) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  Future<void> setVaultPath(String path) async {
    final trimmed = path.trim();
    _obsidian = ObsidianService(trimmed.isEmpty ? defaultVaultPath : trimmed);
    await _prefs?.setString(
      'obsidian_vault_path',
      trimmed.isEmpty ? defaultVaultPath : trimmed,
    );
    if (trimmed.isNotEmpty) {
      await _rememberVault(trimmed);
    }
    notifyListeners();
  }

  List<String> _savedVaultPaths = [];

  /// Ранее использованные пути к vault — для быстрого переключения.
  List<String> get savedVaultPaths => List.unmodifiable(_savedVaultPaths);

  Future<void> _rememberVault(String path) async {
    final list = List<String>.of(_savedVaultPaths)
      ..removeWhere((p) => p == path);
    list.insert(0, path);
    _savedVaultPaths = list.take(8).toList();
    await _prefs?.setStringList('saved_vault_paths', _savedVaultPaths);
  }

  /// Разрешён ли доступ ко всем файлам телефона (Android 11+).
  Future<bool> hasAllFilesAccess() async {
    if (isPc) return true;
    try {
      return await _vaultChannel.invokeMethod<bool>('hasAllFilesAccess') ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// Открывает настройки «Доступ ко всем файлам».
  Future<void> requestAllFilesAccess() async {
    try {
      await _vaultChannel.invokeMethod<void>('requestAllFilesAccess');
    } catch (_) {}
  }

  /// Нативный выбор папки vault на телефоне. Возвращает путь или null.
  Future<String?> pickVaultFolder() async {
    try {
      return await _vaultChannel.invokeMethod<String?>('pickVaultFolder');
    } catch (_) {
      return null;
    }
  }

  // ── Синхронизация с ПК ─────────────────────────────────────────────

  Future<void> setSyncEnabled(bool value) async {
    _syncEnabled = value;
    await _prefs?.setBool('sync_enabled', value);
    if (!isPc) {
      if (value && _syncAddress.trim().isNotEmpty) {
        _startAutoSync();
        unawaited(syncWithPc());
      } else {
        _syncTimer?.cancel();
        _syncTimer = null;
      }
    }
    notifyListeners();
  }

  Future<void> setSyncAddress(String value) async {
    final v = _cleanSyncAddress(value);
    _syncAddress = v;
    await _prefs?.setString('sync_address', _syncAddress);
    if (!isPc &&
        _syncEnabled &&
        _syncAddress.isNotEmpty &&
        _syncTimer == null) {
      _startAutoSync();
      unawaited(syncWithPc());
    }
    notifyListeners();
  }

  /// Приводит адрес ПК к единому виду: без схемы `http://` и лишних слэшей,
  /// чтобы и синк, и проверка обновлений строили корректные URL.
  static String _cleanSyncAddress(String raw) {
    var v = raw.trim();
    v = v.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    while (v.endsWith('/') && v.isNotEmpty) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Future<void> setSyncToken(String value) async {
    _syncToken = value.trim();
    await _prefs?.setString('sync_token', _syncToken);
    if (isPc && syncServerRunning) {
      await _stopSyncServer();
      await _startSyncServer();
    }
    notifyListeners();
  }

  Future<void> setSyncPort(int value) async {
    _syncPort = value;
    await _prefs?.setInt('sync_port', value);
    if (isPc && syncServerRunning) {
      await _stopSyncServer();
      await _startSyncServer();
    }
    notifyListeners();
  }

  Future<void> setSyncServerEnabled(bool value) async {
    _syncServerEnabled = value;
    await _prefs?.setBool('sync_server_enabled', value);
    if (value) {
      await _startSyncServer();
    } else {
      await _stopSyncServer();
    }
    notifyListeners();
  }

  Future<void> _startSyncServer() async {
    try {
      _syncServer = SyncServer(
        db: db,
        obsidian: _obsidian,
        port: _syncPort,
        token: _syncToken,
        onChanged: reloadFromDb,
      );
      await _syncServer!.start();
      _localAddresses = await SyncServer.localAddresses();
    } catch (_) {
      _syncServer = null;
      _localAddresses = const [];
    }
    notifyListeners();
  }

  Future<void> _stopSyncServer() async {
    await _syncServer?.stop();
    _syncServer = null;
    notifyListeners();
  }

  /// Пытается открыть порт в брандмауэре Windows (нужны права администратора).
  /// Возвращает текст с результатом для показа пользователю.
  Future<String> openFirewallPort() async {
    if (!isPc) return strings.t('firewallPcOnly');
    try {
      final res = await Process.run('netsh', [
        'advfirewall',
        'firewall',
        'add',
        'rule',
        'name=KHS sync $_syncPort',
        'dir=in',
        'action=allow',
        'protocol=TCP',
        'localport=$_syncPort',
      ]);
      if (res.exitCode == 0) return strings.t('firewallOpened');
      return '${strings.t('firewallFailed')} (${res.stderr.toString().trim()})';
    } catch (e) {
      return '${strings.t('firewallFailed')} ($e)';
    }
  }

  /// Обновляет списки задач и заметок из БД (после изменения данных
  /// сервером со стороны телефона).
  Future<void> reloadFromDb() async {
    _tasks = await db.getTasks();
    _notes = await db.getNotes();
    _deletedNotes = await db.getDeletedNotes();
    notifyListeners();
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _maybeSync();
    });
  }

  /// Фоновая синхронизация: не запускает повторно, если уже идёт.
  void _maybeSync() {
    if (_syncing) return;
    if (isPc) return;
    if (!_syncEnabled || _syncAddress.trim().isEmpty) return;
    unawaited(syncWithPc());
  }

  /// Полная синхронизация с ПК (телефон). Возвращает результат.
  Future<SyncClientResult> syncWithPc() async {
    if (_syncing) return const SyncClientResult(status: 'busy');
    if (isPc) {
      return const SyncClientResult(status: 'error', error: 'server_platform');
    }
    if (_syncAddress.trim().isEmpty) {
      _lastSyncStatus = 'error';
      notifyListeners();
      return const SyncClientResult(status: 'error', error: 'no_address');
    }
    _syncing = true;
    notifyListeners();
    try {
      final client = SyncClient(db: db, host: _syncAddress, token: _syncToken);
      final result = await client.sync();
      _lastSyncTime = DateTime.now();
      _lastSyncStatus = result.ok
          ? 'ok'
          : (result.status == 'offline' ? 'offline' : 'error');
      if (result.ok) {
        final pcVault = result.vaultPath;
        final localVault = _obsidian.vaultPath.trim();
        final localIsWindowsPath =
            RegExp(r'^[A-Za-z]:[\\/]').hasMatch(localVault);
        if (pcVault != null &&
            pcVault.trim().isNotEmpty &&
            (localVault.isEmpty || localIsWindowsPath)) {
          await setVaultPath(pcVault);
        }
        await reloadFromDb();
        _scheduleAllTaskNotifications();
        _notifyNoteArrivals(result.notesBefore, result.notesAfter);
      }
      notifyListeners();
      return result;
    } catch (e) {
      _lastSyncTime = DateTime.now();
      _lastSyncStatus = 'error';
      notifyListeners();
      return SyncClientResult(status: 'error', error: e);
    } finally {
      _syncing = false;
    }
  }

  /// Проверка доступности ПК по адресу из настроек.
  Future<bool> checkPcConnection() async {
    if (_syncAddress.trim().isEmpty) return false;
    return SyncClient(db: db, host: _syncAddress, token: _syncToken).check();
  }

  /// Проверка сервера на самом ПК (localhost) — чтобы отличить проблемы
  /// брандмауэра/сети от проблем самого сервера.
  Future<bool> checkLocalServer() async {
    if (!isPc) return false;
    return SyncClient(
      db: db,
      host: '127.0.0.1:$_syncPort',
      token: _syncToken,
    ).check();
  }

  /// Проверяет на ПК наличие более новой версии KHS (обновление по Wi-Fi).
  Future<UpdateInfo?> checkForUpdate() async {
    if (_syncAddress.trim().isEmpty) return null;
    return UpdateChecker(host: _syncAddress, token: _syncToken).fetch();
  }

  /// Скачивает файл обновления с ПК в [targetDir].
  Future<File> downloadUpdate(String filename, Directory targetDir) =>
      UpdateChecker(
        host: _syncAddress,
        token: _syncToken,
      ).download(filename, targetDir);

  /// Разрешена ли на Android установка APK «из неизвестных источников».
  Future<bool> canInstallPackages() async {
    if (isPc) return true;
    try {
      return await _installChannel.invokeMethod<bool>(
            'canRequestPackageInstalls',
          ) ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// Открывает системный экран «Разрешить установку из неизвестных источников».
  Future<void> openInstallSourcesSettings() async {
    try {
      await _installChannel.invokeMethod<void>('openInstallSourcesSettings');
    } catch (_) {}
  }

  /// Разрешён ли точный будильник (Android 12+).
  Future<bool> canScheduleExactAlarms() async {
    if (isPc) return true;
    return notifications.canScheduleExactAlarms();
  }

  /// Снимает ли система ограничение на фоновую работу KHS
  /// (оптимизация батареи). Если нет — напоминания могут не прийти,
  /// пока приложение закрыто.
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (isPc) return true;
    try {
      return await _backgroundChannel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// Просит систему не оптимизировать батарею для KHS.
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (isPc) return;
    try {
      await _backgroundChannel.invokeMethod<void>(
        'requestIgnoreBatteryOptimizations',
      );
    } catch (_) {}
  }

  /// Пробное уведомление через 10 секунд.
  Future<void> sendTestNotification() async {
    await notifications.sendTestNotification(
      strings.t('testNotificationTitle'),
      strings.t('testNotificationBody'),
    );
  }

  /// Переназначает напоминания о задачах после синхронизации.
  Future<void> _scheduleAllTaskNotifications() async {
    if (!_notificationsEnabled) return;
    for (final t in _tasks) {
      if (t.id == null || t.completed) continue;
      await _scheduleNotification(t);
    }
  }

  /// Уведомляет о заметках, которые пришли с ПК.
  void _notifyNoteArrivals(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
  ) {
    if (before.isEmpty && after.isNotEmpty) return;
    final beforeByKey = {
      for (final r in before)
        if (r['client_key'] is String) r['client_key'] as String: r,
    };
    for (final r in after) {
      final key = r['client_key'];
      if (key is! String) continue;
      if ((r['deleted'] as int? ?? 0) == 1) continue;
      final prev = beforeByKey[key];
      if (prev == null) {
        final note = Note.fromMap(r);
        unawaited(
          notifications.show(
            900000 + (note.createdAt.millisecondsSinceEpoch % 100000),
            strings.t('newNoteArrived'),
            note.title,
          ),
        );
      }
    }
  }

  // ── Напоминание про заметку дня ───────────────────────────────────

  Future<void> setNoteReminderEnabled(bool value) async {
    _noteReminderEnabled = value;
    await _prefs?.setBool('note_reminder_enabled', value);
    _scheduleNoteReminder();
    notifyListeners();
  }

  Future<void> setNoteReminderMinutes(int minutes) async {
    _noteReminderMinutes = minutes;
    await _prefs?.setInt('note_reminder_minutes', minutes);
    _scheduleNoteReminder();
    notifyListeners();
  }

  Future<void> _scheduleNoteReminder() async {
    if (isPc) return;
    await notifications.cancel(noteReminderNotificationId);
    if (!_noteReminderEnabled) return;
    final now = DateTime.now();
    final hour = _noteReminderMinutes ~/ 60;
    final minute = _noteReminderMinutes % 60;
    var when = DateTime(now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    await notifications.schedule(
      noteReminderNotificationId,
      strings.t('appTitle'),
      strings.t('noteReminderBody'),
      when,
      repeat: DateTimeComponents.time,
    );
  }

  List<Task> get tasksForSelectedDate => tasksForDate(selectedDate);

  /// Задачи дня. Выполненные остаются в списке (внизу, с пометкой),
  /// чтобы было видно, что задача сделана.
  List<Task> tasksForDate(DateTime date) {
    return _tasks
        .where((t) => t.dueAt != null && _sameDay(t.dueAt!, date))
        .toList()
      ..sort(_taskSorter);
  }

  List<Task> get allTasks => _tasks;

  void selectDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (d != _selectedDate) {
      _selectedDate = d;
      notifyListeners();
    }
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    await _prefs?.setString('locale', locale);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    await _prefs?.setInt('accent_color', color.toARGB32());
    notifyListeners();
  }

  Future<void> setDarkTheme(bool value) async {
    if (value == _isDarkTheme) return;
    _isDarkTheme = value;
    await _prefs?.setBool('dark_theme', value);
    notifyListeners();
  }

  Future<void> setDailyGoal(int value) async {
    final clamped = value.clamp(1, 100);
    if (clamped == _dailyGoal) return;
    _dailyGoal = clamped;
    await _prefs?.setInt('daily_goal', clamped);
    notifyListeners();
  }

  Future<void> createGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (!_groups.contains(trimmed)) {
      _groups.add(trimmed);
      await _prefs?.setStringList('groups', _groups);
      notifyListeners();
    }
  }

  Future<void> renameGroup(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == oldName) return;
    final i = _groups.indexOf(oldName);
    if (i != -1) {
      _groups[i] = trimmed;
      await _prefs?.setStringList('groups', _groups);
    }
    for (final t in _tasks.toList()) {
      if (t.category == oldName) {
        await db.updateTask(t.copyWith(category: trimmed));
        final idx = _tasks.indexWhere((x) => x.id == t.id);
        if (idx != -1) _tasks[idx] = t.copyWith(category: trimmed);
      }
    }
    notifyListeners();
  }

  Future<void> deleteGroup(String name) async {
    _groups.remove(name);
    await _prefs?.setStringList('groups', _groups);
    for (final t in _tasks.toList()) {
      if (t.category == name) {
        await db.updateTask(t.copyWith(clearCategory: true));
        final idx = _tasks.indexWhere((x) => x.id == t.id);
        if (idx != -1) _tasks[idx] = t.copyWith(clearCategory: true);
      }
    }
    notifyListeners();
  }

  Future<void> clearReminder(Task task) async {
    await updateTask(task.copyWith(clearReminder: true));
  }

  Future<Note> addNote(String title, String content, {DateTime? date}) async {
    final now = DateTime.now();
    final note = Note(
      title: title.trim(),
      content: content,
      date: date,
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insertNote(note);
    final saved = note.copyWith(id: id);
    _notes.insert(0, saved);
    notifyListeners();
    await _persistNoteToObsidian(saved);
    _maybeSync();
    return saved;
  }

  Future<void> updateNote(Note note) async {
    final updated = note.copyWith(updatedAt: DateTime.now());
    await db.updateNote(updated);
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i != -1) {
      _notes[i] = updated;
    } else {
      _notes.add(updated);
    }
    _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
    await _persistNoteToObsidian(updated);
    _maybeSync();
  }

  Future<void> deleteNote(Note note) async {
    await db.deleteNote(note.id!);
    _notes.removeWhere((n) => n.id == note.id);
    final removed = note.copyWith(deleted: true, updatedAt: DateTime.now());
    _deletedNotes = [removed, ..._deletedNotes];
    notifyListeners();
    final d = note.date;
    if (_obsidian.isConfigured) {
      try {
        if (d == null) {
          await _obsidian.deleteStandaloneNote(note);
        } else {
          await _obsidian.writeDailyNote(d, body: '');
        }
      } catch (_) {}
    }
    _maybeSync();
  }

  /// Восстановить заметку из корзины.
  Future<void> restoreNote(Note note) async {
    await db.restoreNote(note.id!);
    _deletedNotes.removeWhere((n) => n.id == note.id);
    final restored = note.copyWith(deleted: false, updatedAt: DateTime.now());
    _notes = [restored, ..._notes];
    notifyListeners();
    _maybeSync();
  }

  /// Полное удаление заметки (необратимо).
  Future<void> deleteNoteForever(Note note) async {
    await db.purgeNote(note.id!);
    _deletedNotes.removeWhere((n) => n.id == note.id);
    notifyListeners();
    _maybeSync();
  }

  /// Заметки, относящиеся к дню (заметка дня по своей дате,
  /// отдельные заметки — по дате создания).
  List<Note> notesForDate(DateTime date) {
    return _notes.where((n) => _sameDay(n.date ?? n.createdAt, date)).toList();
  }

  bool hasNotesOn(DateTime date) => notesForDate(date).isNotEmpty;

  /// Пишет заметку в Obsidian (если vault настроен): ежедневную — в блок
  /// ежедневной заметки с задачами дня, отдельную (без даты) — отдельным
  /// файлом в папке «заметки».
  Future<void> _persistNoteToObsidian(Note note) async {
    final d = note.date;
    if (!_obsidian.isConfigured) return;
    try {
      if (d == null) {
        await _obsidian.writeStandaloneNote(note);
      } else {
        await _obsidian.writeDailyNote(
          d,
          body: note.content,
          tasks: tasksForDate(d),
        );
      }
    } catch (_) {}
  }

  /// Создаёт сегодняшние экземпляры для ежедневных повторяющихся задач,
  /// если их ещё нет. Вызывается при запуске и при возвращении в приложение.
  Future<void> _ensureDailyOccurrences() async {
    final today = _today();
    final dailyTasks = _tasks.where(
      (t) => t.recurrence == 'daily' && t.clientKey != null,
    );
    for (final template in dailyTasks) {
      final alreadyToday = _tasks.any((t) =>
          t.id != template.id &&
          t.clientKey == template.clientKey &&
          t.dueAt != null &&
          _sameDay(t.dueAt!, today));
      if (!alreadyToday) {
        final next = template.copyWith(
          id: null,
          dueAt: DateTime(today.year, today.month, today.day,
              template.dueAt?.hour ?? 9, template.dueAt?.minute ?? 0),
          completed: false,
          createdAt: DateTime.now(),
          completedAt: null,
        );
        final nextId = await db.insertTask(next);
        final saved = next.copyWith(id: nextId);
        _tasks.add(saved);
        await _scheduleNotification(saved);
      }
    }
    notifyListeners();
  }

  bool get isRussian => strings.isRussian;

  ParsedTask parseQuick(String input) => parser.parse(input);

  Future<Task> addTask(Task task) async {
    final id = await db.insertTask(task);
    final saved = task.copyWith(id: id);
    _tasks.add(saved);
    await _scheduleNotification(saved);
    notifyListeners();
    _maybeSync();
    return saved;
  }

  Future<void> updateTask(Task task) async {
    await db.updateTask(task);
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i != -1) {
      _tasks[i] = task;
    } else {
      _tasks.add(task);
    }
    await notifications.cancel(task.id!);
    await _scheduleNotification(task);
    notifyListeners();
    _maybeSync();
  }

  Future<void> toggleCompleted(Task task) async {
    if (!task.completed && task.isRecurring && task.dueAt != null) {
      if (task.recurrence != 'daily') {
        final next = task.nextOccurrence();
        final nextDue = next.dueDate;
        final alreadyExists = _tasks.any((t) =>
            t.id != task.id &&
            t.title.trim().toLowerCase() == task.title.trim().toLowerCase() &&
            t.dueDate != null &&
            nextDue != null &&
            t.dueDate!.year == nextDue.year &&
            t.dueDate!.month == nextDue.month &&
            t.dueDate!.day == nextDue.day);
        if (!alreadyExists) {
          final nextId = await db.insertTask(next);
          final savedNext = next.copyWith(id: nextId);
          _tasks.add(savedNext);
          await _scheduleNotification(savedNext);
        }
      }
    }
    final updated = task.withCompleted(!task.completed);
    await db.updateTask(updated);
    final i = _tasks.indexWhere((t) => t.id == updated.id);
    if (i != -1) _tasks[i] = updated;
    await notifications.cancel(task.id!);
    notifyListeners();
    _maybeSync();
  }

  Future<void> deleteTask(Task task) async {
    await db.deleteTask(task.id!);
    _tasks.removeWhere((t) => t.id == task.id);
    await notifications.cancel(task.id!);
    notifyListeners();
    _maybeSync();
  }

  bool get notificationsEnabled => _notificationsEnabled;

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    await _prefs?.setBool('notifications_enabled', value);
    notifyListeners();
    for (final t in _tasks) {
      if (t.id == null || t.completed) continue;
      if (value) {
        await _scheduleNotification(t);
      } else {
        await notifications.cancel(t.id!);
      }
    }
  }

  Future<void> _scheduleNotification(Task task) async {
    if (!_notificationsEnabled) return;
    if (!task.notify) return;
    final reminder = task.reminderAt;
    if (reminder != null && reminder.isAfter(DateTime.now())) {
      await notifications.schedule(
        task.id!,
        strings.t('appTitle'),
        task.title,
        reminder,
      );
    }
  }

  Task? _findMatching(Task other) {
    final normalized = other.title.trim().toLowerCase();
    final otherDue = other.dueDate;
    for (final t in _tasks) {
      if (t.title.trim().toLowerCase() != normalized) continue;
      final due = t.dueDate;
      if (due == null && otherDue == null) return t;
      if (due != null &&
          otherDue != null &&
          due.year == otherDue.year &&
          due.month == otherDue.month &&
          due.day == otherDue.day) {
        return t;
      }
    }
    return null;
  }

  bool _relevantForToday(Task t, DateTime today) {
    final due = t.dueDate;
    if (due != null) {
      return due.year == today.year &&
          due.month == today.month &&
          due.day == today.day;
    }
    return !t.completed;
  }

  Future<ObsidianSyncResult> syncWithObsidian() async {
    if (!_obsidian.isConfigured) {
      return const ObsidianSyncResult(error: 'noVaultPath');
    }
    final today = _today();
    int added = 0;
    int updated = 0;

    final imported = await _obsidian.readTasks(today);
    for (final task in imported) {
      final existing = _findMatching(task);
      if (existing == null) {
        final saved = await db.insertTask(task);
        final stored = task.copyWith(id: saved);
        _tasks.add(stored);
        await _scheduleNotification(stored);
        added++;
      } else if (existing.completed != task.completed) {
        final changed = existing.copyWith(
          completed: task.completed,
          completedAt: task.completed
              ? (task.completedAt ?? DateTime.now())
              : null,
          clearCompletedAt: !task.completed,
        );
        await db.updateTask(changed);
        final i = _tasks.indexWhere((t) => t.id == changed.id);
        if (i != -1) _tasks[i] = changed;
        updated++;
      }
    }

    final toExport = _tasks.where((t) => _relevantForToday(t, today)).toList();
    await _obsidian.writeTasks(today, toExport);
    notifyListeners();
    return ObsidianSyncResult(
      added: added,
      updated: updated,
      written: toExport.length,
    );
  }
}

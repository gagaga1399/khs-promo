import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (Platform.isWindows) {
      FlutterLocalNotificationsPlatform.instance =
          FlutterLocalNotificationsWindows();
    }
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windows = WindowsInitializationSettings(
      appName: 'KHS',
      appUserModelId: 'khs.khs',
      guid: '90a4b2c8-9d3e-4b1a-8c0f-5e7d6a4b3c21',
    );
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');
    const settings = InitializationSettings(
      android: android,
      windows: windows,
      linux: linux,
    );
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  Future<void> requestPermissions() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  }

  /// Разрешены ли точные будильники (Android 12+). Если нет — уведомление
  /// может прийти с задержкой.
  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidImpl?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Тестовое уведомление через 10 секунд — проверить доставку.
  Future<void> sendTestNotification(String title, String body) async {
    if (!_ready) return;
    await schedule(
      999001,
      title,
      body,
      DateTime.now().add(const Duration(seconds: 10)),
    );
  }

  NotificationDetails _details() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders',
        'Task reminders',
        channelDescription: 'Notifications about task due dates',
        importance: Importance.max,
        priority: Priority.high,
      ),
      windows: const WindowsNotificationDetails(
        scenario: WindowsNotificationScenario.reminder,
      ),
      linux: const LinuxNotificationDetails(defaultActionName: 'Open'),
    );
  }

  /// Мгновенное уведомление (например, заметка, пришедшая с ПК).
  Future<void> show(int id, String title, String body) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details(),
    );
  }

  Future<void> schedule(
    int id,
    String title,
    String body,
    DateTime when, {
    DateTimeComponents? repeat,
  }) async {
    if (!_ready) return;
    final scheduled = tz.TZDateTime.from(when, tz.local);
    try {
      // Точный будильник, чтобы уведомление пришло вовремя. Требует
      // SCHEDULE_EXACT_ALARM; если пользователь запретил — запасной вариант.
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduled,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: repeat,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduled,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: repeat,
      );
    }
  }

  Future<void> cancel(int id) => _plugin.cancel(id: id);

  Future<void> cancelAll() => _plugin.cancelAll();
}

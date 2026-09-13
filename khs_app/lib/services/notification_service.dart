import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'khs_reminders';
  static const _channelName = 'Напоминания задач';
  static const _channelDesc = 'Уведомления о сроках задач и напоминания';

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

    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }

    _ready = true;
  }

  Future<void> _createNotificationChannel() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl == null) return;
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      enableVibration: true,
      enableLights: true,
      playSound: true,
    );
    await androidImpl.createNotificationChannel(channel);
  }

  Future<void> requestPermissions() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  }

  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidImpl?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendTestNotification(String title, String body) async {
    if (!_ready) return;
    await show(999001, title, body);
  }

  NotificationDetails _details() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        enableLights: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(''),
      ),
      windows: const WindowsNotificationDetails(
        scenario: WindowsNotificationScenario.reminder,
      ),
      linux: const LinuxNotificationDetails(defaultActionName: 'Open'),
    );
  }

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

    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;

    try {
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
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduled,
          notificationDetails: _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: repeat,
        );
      } catch (_) {}
    }
  }

  Future<void> cancel(int id) => _plugin.cancel(id: id);

  Future<void> cancelAll() => _plugin.cancelAll();
}

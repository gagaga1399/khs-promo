import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart'
    show
        DidReceiveNotificationResponseCallback,
        DidReceiveBackgroundNotificationResponseCallback,
        DateTimeComponents,
        FlutterLocalNotificationsPlatform,
        NotificationAppLaunchDetails,
        RepeatInterval;

import 'package:timezone/timezone.dart' as tz;

/// WindowsInitializationSettings compatible with the real plugin API.
class WindowsInitializationSettings {
  const WindowsInitializationSettings({
    required this.appName,
    required this.appUserModelId,
    required this.guid,
    this.iconPath,
  });

  final String appName;
  final String appUserModelId;
  final String guid;
  final String? iconPath;
}

/// The scenario a Windows notification is used for.
enum WindowsNotificationScenario {
  reminder,
  alarm,
  incomingCall,
  urgent,
}

/// WindowsNotificationDetails compatible with the real plugin API.
class WindowsNotificationDetails {
  const WindowsNotificationDetails({
    this.scenario,
    this.subtitle,
    this.timestamp,
    this.duration,
    this.header,
    this.audio,
    this.sound,
    this.progress = 0,
  });

  final WindowsNotificationScenario? scenario;
  final String? subtitle;
  final DateTime? timestamp;
  final Object? duration;
  final Object? header;
  final Object? audio;
  final Object? sound;
  final int progress;
}

/// No-op implementation of the Windows notifications plugin.
///
/// Used to compile and run the app on Windows without the native plugin.
class FlutterLocalNotificationsWindows extends FlutterLocalNotificationsPlatform {
  FlutterLocalNotificationsWindows();

  Future<bool?> initialize({
    required WindowsInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async {
    return const NotificationAppLaunchDetails(false);
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    WindowsNotificationDetails? notificationDetails,
    String? payload,
  }) async {}

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    WindowsNotificationDetails? notificationDetails,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {}

  @override
  Future<void> periodicallyShow({
    required int id,
    String? title,
    String? body,
    required RepeatInterval repeatInterval,
    WindowsNotificationDetails? notificationDetails,
    String? payload,
  }) async {}

  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<void> cancelAll() async {}
}

import 'dart:io';

import 'package:flutter/services.dart';

/// Ярлыки на рабочий стол Android (закрепить как приложение).
/// На Windows используется PowerShell-скрипт из hub_screen.
class LauncherShortcut {
  static const _channel = MethodChannel('khs/shortcut');

  /// Запуск приложения через закреплённый ярлык «KHS Tasks».
  static bool startTasks = false;

  /// Стартовый флаг из intent (Android) — «открыть сразу KHS Tasks».
  static Future<String?> initialStart() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getInitialStart');
    } catch (_) {
      return null;
    }
  }

  /// Запросить у системы закрепление ярлыка «KHS Tasks» на домашнем экране.
  /// Возвращает false, если устройство не поддерживает (до Android 8).
  static Future<bool> createTasksShortcut(String label) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'createTasksShortcut',
        {'label': label},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Установлено ли приложение на Android.
  static Future<bool> isPackageInstalled(String package) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('isPackageInstalled', {'package': package});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Версия установленного приложения (versionName) на Android, либо null.
  static Future<String?> getPackageVersion(String package) async {
    if (!Platform.isAndroid) return null;
    try {
      final v = await _channel
          .invokeMethod<String>('getPackageVersion', {'package': package});
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Запустить приложение; если его нет — открыть ссылку [fallbackUrl].
  static Future<bool> launchPackage(
    String package, {
    String? fallbackUrl,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'launchPackage',
        {
          'package': package,
          'fallbackUrl': ?fallbackUrl,
        },
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Закрепить ярлык установленного приложения на домашнем экране Android.
  static Future<bool> createAppShortcut(String package, String label) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'createAppShortcut',
        {'package': package, 'label': label},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Событие от системы: приложение уже запущено и добили по ярлыку.
  static void listenStartTasks(void Function() onStart) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'startTasks') {
        startTasks = true;
        onStart();
      }
    });
  }
}
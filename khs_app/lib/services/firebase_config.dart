import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

/// Параметры проекта Firebase `khs-hub`.
///
/// Заданы прямо в коде, а не читаются из google-services.json: приложение
/// одно, а конфиг нужен одинаково на Windows и Android, и не нужно держать
/// файл, который ломает сборку, если его забыли положить в репозиторий.
class KhsFirebase {
  const KhsFirebase._();

  static const String projectId = 'khs-hub';
  static const String appId = '1:815286705963:web:2c6f8bba1da500b9c8ef6e';
  static const String apiKey = 'AIzaSyCu9JsnivP-XAokS-dxH3hU_R-vlb8_Njc';
  static const String messagingSenderId = '815286705963';
  static const String authDomain = 'khs-hub.firebaseapp.com';
  static const String storageBucket = 'khs-hub.firebasestorage.app';

  /// OAuth-клиент для входа кнопкой Google (создан Firebase при включении
  /// провайдера). На Windows это clientId, на Android — serverClientId,
  /// поэтому значение одно для обоих.
  static const String googleClientId =
      '815286705963-ieik21cq6aaq6j2bq1tiqumeug0gfha8.apps.googleusercontent.com';

  /// Клиент типа Desktop app. Создан в Google Cloud Console → «Учётные данные
  /// OAuth» → «Создать клиент» → «Приложение для ПК».
  ///
  /// Сейчас не используется: окно входа на ПК его не открывает, потому что у
  /// `google_sign_in` нет реализации для Windows. Нужен будет, если вход на ПК
  /// появится.
  static const String googleDesktopClientId =
      '815286705963-lmrutr1ggnse2hj2ju7hs8nmido4jv19.apps.googleusercontent.com';

  /// Клиент, который открывает окно входа. На Android окно рисует система через
  /// Play Services, и clientId там не используется.
  static String get googleSignInClientId =>
      (Platform.isWindows && googleDesktopClientId.trim().isNotEmpty)
      ? googleDesktopClientId
      : googleClientId;

  /// Чей токен уходит в Firebase. Firebase проверяетaudience токена по всем
  /// OAuth-клиентам проекта, поэтому подходит веб-клиент: он же попадает в
  /// google-services.json для Android.
  static String get googleServerClientId => googleClientId;

  /// Пункт «Аккаунт» открыт: Email/пароль проверен на живом проекте khs-hub
  /// (регистрация и вход проходят). Кнопка Google показывается только там,
  /// где вход технически возможен.
  static const bool accountFeatureEnabled = true;

  static const FirebaseOptions options = FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: authDomain,
    storageBucket: storageBucket,
  );

  /// Настроен ли вход через Google.
  ///
  /// На Windows входа нет: в `google_sign_in` 7.x реализация только для
  /// Android, iOS и web, пакета `google_sign_in_windows` в зависимостях нет,
  /// а в `windows/flutter/generated_plugin_registrant.cc` нет ни одного
  /// Google-плагина. Вызов уходит в пустоту и падает с `UnimplementedError`,
  /// поэтому кнопку Google на ПК показывать нельзя — она гарантированно
  /// отказывает. На Android и вход по Email работают.
  static bool get googleReady =>
      googleClientId.trim().isNotEmpty && !Platform.isWindows;
}

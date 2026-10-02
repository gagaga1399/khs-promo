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

  /// OAuth-клиент для входа кнопкой Google. Firebase создаёт его сам, когда
  /// провайдер Google включают в консоли; пока пусто — кнопка сообщает, что
  /// вход ещё не настроен, а не падает.
  static const String googleClientId = '';

  static const FirebaseOptions options = FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: authDomain,
    storageBucket: storageBucket,
  );

  /// Настроен ли вход через Google (нужен client id провайдера).
  static bool get googleReady => googleClientId.trim().isNotEmpty;
}

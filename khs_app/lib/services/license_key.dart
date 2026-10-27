/// Ключ разблокировки раздела «Трекеры».
///
/// Раздел закрыт, пока пользователь не введёт верный ключ в настройках хаба.
/// Ключ зашит в приложение; проверка — точное совпадение (после нормализации
/// регистра и пробелов).
class LicenseKey {
  LicenseKey._();

  /// Сгенерированный ключ. Именно он открывает трекеры. Подобран из простых
  /// слов, чтобы его легко запомнить.
  static const String valid = 'KHS-ЛЕС-СВЕТ-ДОМ';

  /// Нормализация ввода: без пробелов, в верхнем регистре.
  static String normalize(String input) => input
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('-', '');

  /// Верен ли введённый ключ.
  static bool isValid(String input) {
    if (input.trim().isEmpty) return false;
    return normalize(input) == normalize(valid);
  }
}

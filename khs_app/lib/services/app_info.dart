import 'package:package_info_plus/package_info_plus.dart';

/// Версия приложения из pubspec.yaml (кэшируется после первой загрузки).
class AppInfo {
  static String? _version;

  static Future<String?> version() async {
    if (_version != null) return _version;
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      return _version;
    } catch (_) {
      return null;
    }
  }
}

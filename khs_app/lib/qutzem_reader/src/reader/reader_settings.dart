import 'package:shared_preferences/shared_preferences.dart';

import 'theme_data.dart';

/// Персистентные настройки чтения (тема/шрифт/режим/колонки).
///
/// Хранятся глобально через [SharedPreferences]. Запоминаются между
/// сессиями, как в Elton Reader.
class ReaderSettingsStore {
  ReaderSettingsStore._();
  static final ReaderSettingsStore instance = ReaderSettingsStore._();

  static const double defaultFont = 18;
  static const String _prefix = 'reader_';

  bool _loaded = false;
  final Map<String, dynamic> _cache = {};

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_prefix)) {
        _cache[key.substring(_prefix.length)] = prefs.get(key);
      }
    }
    _loaded = true;
  }

  Future<T?> _get<T>(String key) async {
    await _ensureLoaded();
    return _cache[key] as T?;
  }

  Future<void> _set(String key, Object value) async {
    await _ensureLoaded();
    _cache[key] = value;
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(_prefix + key, value);
    } else if (value is double) {
      await prefs.setDouble(_prefix + key, value);
    } else if (value is int) {
      await prefs.setInt(_prefix + key, value);
    } else if (value is bool) {
      await prefs.setBool(_prefix + key, value);
    }
  }

  Future<double> fontSize({bool spread = true}) async =>
      await _get<double>(spread ? 'fontSize' : 'fontSizeText') ?? defaultFont;

  Future<void> setFontSize(double v, {bool spread = true}) =>
      _set(spread ? 'fontSize' : 'fontSizeText', v);

  Future<ReaderTheme> theme() async =>
      ReaderThemeExt.fromName(await _get<String>('theme'));

  Future<void> setTheme(ReaderTheme t) => _set('theme', t.name);

  Future<bool> scrollMode() async =>
      await _get<bool>('scrollMode') ?? true;

  Future<void> setScrollMode(bool v) => _set('scrollMode', v);

  Future<bool> twoColumns() async =>
      await _get<bool>('twoColumns') ?? true;

  Future<void> setTwoColumns(bool v) => _set('twoColumns', v);
}

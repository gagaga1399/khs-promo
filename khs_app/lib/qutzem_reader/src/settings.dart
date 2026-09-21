import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai.dart';
import 'search.dart';

const String appVersion = '1.1.0';

class AppSettings {
  double maxBookSizeBytes;
  List<OpdsCatalog> catalogs;
  AiSettings ai;
  String displayName;
  String syncServer;

  AppSettings({
    this.maxBookSizeBytes = 2 * 1024 * 1024,
    this.catalogs = const [],
    AiSettings? ai,
    this.displayName = 'QutZem Reader',
    this.syncServer = '',
  }) : ai = ai ?? AiSettings();

  Map<String, dynamic> toJson() => {
        'maxBookSizeBytes': maxBookSizeBytes,
        'catalogs': catalogs.map((c) => c.toJson()).toList(),
        'ai': ai.toJson(),
        'displayName': displayName,
        'syncServer': syncServer,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        maxBookSizeBytes: (json['maxBookSizeBytes'] as num?)?.toDouble() ??
            2 * 1024 * 1024,
        catalogs: (json['catalogs'] as List<dynamic>? ?? [])
            .map((e) => OpdsCatalog.fromJson(e as Map<String, dynamic>))
            .toList(),
        ai: AiSettings.fromJson(json['ai'] as Map<String, dynamic>?),
        displayName: json['displayName'] as String? ?? 'QutZem Reader',
        syncServer: json['syncServer'] as String? ?? '',
      );
}

class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  AppSettings _settings = AppSettings();
  AppSettings get oo => _settings;

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('settings') ?? SettingsStore.old;
    if (raw.isNotEmpty) {
      try {
        _settings = AppSettings.fromJson(jsonDecode(raw));
      } catch (_) {
        _settings = AppSettings();
      }
    } else {
      _settings = AppSettings();
    }
    if (_settings.catalogs.isEmpty) {
      _settings.catalogs = SearchService.defaultCatalogs;
    }
    return _settings;
  }

  static const old = '';

  Future<void> save(AppSettings settings) async {
    _settings = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(settings.toJson()));
  }
}
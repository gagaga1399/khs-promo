import 'dart:convert';
import 'dart:io';

import 'releases.dart';

/// Метаданные обновления, которое раздаёт ПК (файл update.json на сервере).
class UpdateInfo {
  final String version;
  final String notes;
  final String? androidFile;
  final int? androidSize;
  final String? windowsFile;
  final int? windowsSize;

  /// Полная история версий с сервера (актуальная даже на старых клиентах).
  final List<ReleaseInfo> history;

  const UpdateInfo({
    required this.version,
    required this.notes,
    this.androidFile,
    this.androidSize,
    this.windowsFile,
    this.windowsSize,
    this.history = const [],
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    version: json['version'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    androidFile: json['android'] as String?,
    androidSize: json['android_size'] as int?,
    windowsFile: json['windows'] as String?,
    windowsSize: json['windows_size'] as int?,
    history: [
      for (final row in (json['history'] as List? ?? []))
        if (row is Map<String, dynamic>)
          ReleaseInfo(
            version: row['version'] as String? ?? '',
            date: row['date'] as String? ?? '',
            changes: [
              for (final c in (row['changes'] as List? ?? []))
                if (c is String) c,
            ],
          ),
    ],
  );
}

/// Ходит на ПК (тот же адрес, что и синк) и спрашивает про обновления.
class UpdateChecker {
  final String host; // например 192.168.1.5:4680
  final String token;

  UpdateChecker({required this.host, required this.token});

  String get _authQuery =>
      token.isEmpty ? '' : '?token=${Uri.encodeQueryComponent(token)}';

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    ..idleTimeout = const Duration(seconds: 20);

  /// Возвращает метаданные обновления или null, если ПК недоступен
  /// или обновление не настроено.
  Future<UpdateInfo?> fetch() async {
    final client = _client();
    try {
      final req = await client.getUrl(
        Uri.parse('http://$host/api/v1/update$_authQuery'),
      );
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final text = await utf8.decoder.bind(res).join();
      return UpdateInfo.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// URL файла обновления на сервере (вынесен отдельно для тестов).
  Uri _fileUrl(String filename) =>
      Uri.parse('http://$host/files/${_safeName(filename)}$_authQuery');

  /// Скачивает файл обновления с ПК в [targetDir].
  Future<File> download(String filename, Directory targetDir) async {
    final file = File(
      '${targetDir.path}${Platform.pathSeparator}${_safeName(filename)}',
    );
    final client = _client();
    try {
      final req = await client.getUrl(_fileUrl(filename));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final sink = file.openWrite();
      try {
        await res.pipe(sink);
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      client.close();
    }
  }

  String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'update' : cleaned;
  }
}

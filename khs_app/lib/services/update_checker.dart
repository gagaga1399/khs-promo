import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'releases.dart';
import 'update_signing.dart';

/// Метаданные обновления, которое раздаёт ПК (файл update.json на сервере).
class UpdateInfo {
  final String version;
  final String notes;
  final String? androidFile;
  final int? androidSize;
  final String? androidSha256;
  final String? windowsFile;
  final int? windowsSize;
  final String? windowsSha256;

  /// Связанная читалка QutZem Reader: файл и целевая версия с ПК.
  final String? readerFile;
  final int? readerSize;
  final String? readerSha256;
  final String? readerVersion;

  /// Полная история версий с сервера (актуальная даже на старых клиентах).
  final List<ReleaseInfo> history;

  const UpdateInfo({
    required this.version,
    required this.notes,
    this.androidFile,
    this.androidSize,
    this.androidSha256,
    this.windowsFile,
    this.windowsSize,
    this.windowsSha256,
    this.readerFile,
    this.readerSize,
    this.readerSha256,
    this.readerVersion,
    this.history = const [],
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    version: json['version'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    androidFile: json['android'] as String?,
    androidSize: json['android_size'] as int?,
    androidSha256: json['android_sha256'] as String?,
    windowsFile: json['windows'] as String?,
    windowsSize: json['windows_size'] as int?,
    windowsSha256: json['windows_sha256'] as String?,
    readerFile: json['reader'] as String?,
    readerSize: json['reader_size'] as int?,
    readerSha256: json['reader_sha256'] as String?,
    readerVersion: (json['reader_version'] as String? ?? '').trim().isNotEmpty
        ? (json['reader_version'] as String).trim()
        : null,
    history: [
      for (final row in (json['history'] as List? ?? []))
        if (row is Map<String, dynamic>)
          ReleaseInfo(
            version: row['version'] as String? ?? '',
            date: row['date'] as String? ?? '',
            changes: [
              for (final c in (row['changes'] as List? ?? []))
                if (c is String) ChangeEntry(c),
            ],
          ),
    ],
  );
}

/// Состояние ответа сервера на проверку обновления: чтобы отличать «сервер
/// недоступен» от «сервер доступен, но обновление на нём не настроено».
enum UpdateCheckStatus {
  ok,
  unreachable,
  noUpdate,

  /// Ответ есть, но подпись не сходится: файл подменён или повреждён.
  ///
  /// Раньше такой ответ молча превращался в [noUpdate], и пользователь видел
  /// «обновлений нет» — то есть испорченные данные выглядели как отсутствие
  /// обновления. Обновление при этом по-прежнему не предлагается, но и
  /// молчать о проблеме нельзя.
  badSignature,
}

/// Откуда пришли метаданные обновления и откуда качать сами файлы.
enum UpdateSource {
  /// Интернет: публичная страница проекта с update.json и файлами.
  web,

  /// Домашний ПК по Wi-Fi (как раньше).
  pc,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateInfo? info;

  /// Источник, на котором ответил сервер; null, если ответа не было.
  final UpdateSource? source;

  const UpdateCheckResult(this.status, [this.info, this.source]);
}

/// Версия из ответа источника, если ответ вообще состоялся.
String? _resultVersion(UpdateCheckResult? r) {
  final v = r?.info?.version.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// Из двух ответов выбирает тот, где версия новее.
///
/// Компьютер может отдавать более свежую сборку, чем лежит в интернете:
/// новую версию собрали, но ещё не опубликовали. Раньше интернет отвечал
/// первым и полностью перехватывал проверку, поэтому такая сборка была
/// недоступна — приходилось публиковать сайт заранее.
UpdateCheckResult? newestOf(UpdateCheckResult? a, UpdateCheckResult? b) {
  final va = _resultVersion(a);
  final vb = _resultVersion(b);
  if (va == null) return b;
  if (vb == null) return a;
  return compareVersions(va, vb) >= 0 ? a : b;
}

/// Выбирает, что показать пользователю, из ответов интернета и ПК.
///
/// Оба ответа могут быть null — источник не опрашивался. Подписанные данные
/// (`ok`) приоритетнее: если их дал хотя бы один источник, берём более новую
/// версию. Дальше — чтобы не пугать «сервер недоступен», когда один из
/// источников жив и просто сообщил, что обновлений нет.
UpdateCheckResult pickUpdateResult({
  UpdateCheckResult? web,
  UpdateCheckResult? pc,
}) {
  final ok = newestOf(
    web?.status == UpdateCheckStatus.ok ? web : null,
    pc?.status == UpdateCheckStatus.ok ? pc : null,
  );
  if (ok != null) return ok;

  // Из остальных ответов битая подпись важнее «обновлений нет»: это не
  // отсутствие обновления, а «данным верить нельзя», и молчать об этом
  // неправильно. Если подпись битая хотя бы у одного источника — сообщаем
  // об этом, даже когда другой источник жив.
  for (final r in [web, pc]) {
    if (r?.status == UpdateCheckStatus.badSignature) return r!;
  }

  if (pc?.status == UpdateCheckStatus.unreachable &&
      web?.status == UpdateCheckStatus.noUpdate) {
    return web!;
  }
  if (web?.status == UpdateCheckStatus.unreachable &&
      pc?.status == UpdateCheckStatus.noUpdate) {
    return pc!;
  }
  return pc ?? web ?? const UpdateCheckResult(UpdateCheckStatus.unreachable);
}

/// Где лежат обновления в интернете по умолчанию.
const String kUpdateWebBaseUrl = 'https://gagaga1399.github.io/khs-promo';

/// Откуда именно качаются файлы в интернете.
///
/// Раньше файлы лежали рядом с update.json в корне сайта, и их приходилось
/// каждый раз коммитить в git: APK весит около 80 МБ, поэтому релиз
/// публиковался, а скачивание отдавало 404 — ровно это и случилось с 1.2.32.
/// Файлы живут в GitHub Releases, страница с ними всегда указывает на
/// последний релиз, и в git больше ничего тащить не нужно.
const String kUpdateWebFileBaseUrl =
    'https://github.com/gagaga1399/khs-promo/releases/latest/download';

/// Спрашивает про обновления сначала в интернете, а если там не вышло —
/// у ПК по Wi-Fi (тот же адрес, что и у синхронизации).
class UpdateChecker {
  final String host; // например 192.168.1.5:4680
  final String token;

  /// Адрес публичной страницы с update.json. Пусто — только ПК.
  final String? webBaseUrl;

  /// Адрес, откуда качаются сами файлы. По умолчанию — последний релиз.
  final String? webFileBaseUrl;

  UpdateChecker({
    required this.host,
    required this.token,
    this.webBaseUrl = kUpdateWebFileBaseUrl,
    this.webFileBaseUrl = kUpdateWebFileBaseUrl,
    this.responseTimeout = defaultResponseTimeout,
    this.stallTimeout = defaultStallTimeout,
  });

  /// Сколько ждать ответа сервера. Раньше ответа ждали без предела: если
  /// сервер принимает соединение и не отвечает, окно обновления висело
  /// бесконечно.
  static const Duration defaultResponseTimeout = Duration(seconds: 20);

  /// Сколько ждать следующую порцию данных. Соединение может принять запрос
  /// и замолчать посреди файла, и без этого загрузка ждала бы вечно.
  static const Duration defaultStallTimeout = Duration(seconds: 30);

  /// В тестах подставляют короткие значения, чтобы не ждать реальные
  /// двадцать секунд на каждый заведомо зависший сервер.
  final Duration responseTimeout;
  final Duration stallTimeout;

  /// Интернет без HTTPS опасен: подпись проверяет файл, но не защищает от
  /// подмены самого ответа. Поэтому молча уходим на ПК, а не качаем.
  /// Исключение — сам компьютер (127.0.0.1): такие адреса не выходят в сеть,
  /// на них удобно гонять локальный сервер при разработке и в тестах.
  bool get webUsable {
    final base = (webBaseUrl?.trim() ?? '').toLowerCase();
    if (base.isEmpty) return false;
    if (base.startsWith('https://')) return true;
    final hostPart = base
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first;
    final hostOnly = hostPart.split(':').first;
    return hostOnly == '127.0.0.1' || hostOnly == 'localhost';
  }

  Map<String, String> _authHeaders() =>
      token.isEmpty ? const <String, String>{} : {'X-KHS-Token': token};

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    // Большой файл качается не мгновенно, но и молчать дольше получаса
    // сервер не может: раньше здесь стояло 180 секунд, и обрыв выглядел
    // как «загрузка идёт».
    ..idleTimeout = stallTimeout;

  /// Спрашивает про обновление. [UpdateCheckResult.status] различает:
  /// `ok` — сервер ответил подписанными данными; `noUpdate` — сервер
  /// доступен, но обновления на нём нет (404/запрет/плохая подпись);
  /// `unreachable` — до сервера не достучаться или ответ не похож на обновление.
  Future<UpdateCheckResult> fetch() async {
    // Интернет и ПК опрашиваем одновременно, а не по очереди: проверка не
    // растягивается на сумму двух ожиданий. Оба Future создаются до первого
    // await, поэтому запросы реально идут параллельно.
    final webFuture = webUsable
        ? _fetchFrom(UpdateSource.web)
        : Future<UpdateCheckResult?>.value();
    final pcFuture = host.trim().isEmpty
        ? Future<UpdateCheckResult?>.value()
        : _fetchFrom(UpdateSource.pc);

    final web = await webFuture;
    final pc = await pcFuture;
    return pickUpdateResult(web: web, pc: pc);
  }

  Future<UpdateCheckResult> _fetchFrom(UpdateSource source) async {
    final client = _client();
    try {
      final req = await client.getUrl(metaUrl(source));
      if (source == UpdateSource.pc) _authHeaders().forEach(req.headers.set);
      final res = await req.close().timeout(responseTimeout);
      if (res.statusCode == 404 ||
          res.statusCode == 403 ||
          res.statusCode == 429) {
        return UpdateCheckResult(UpdateCheckStatus.noUpdate, null, source);
      }
      if (res.statusCode != 200) {
        return const UpdateCheckResult(UpdateCheckStatus.unreachable);
      }
      final text = await utf8.decoder.bind(res).join();
      final json = jsonDecode(text) as Map<String, dynamic>;
      // Без валидной подписи обновление не предлагаем вообще — так
      // «по дороге» нельзя подменить update.json или файлы. Но молчать о
      // такой подмене нельзя: пользователь должен знать, что источнику
      // верить нельзя, поэтому это отдельный статус, а не «обновлений нет».
      if (!await verifyUpdateSignature(json)) {
        return UpdateCheckResult(UpdateCheckStatus.badSignature, null, source);
      }
      final info = UpdateInfo.fromJson(json);
      if (info.version.isEmpty) {
        return UpdateCheckResult(UpdateCheckStatus.noUpdate, info, source);
      }
      return UpdateCheckResult(UpdateCheckStatus.ok, info, source);
    } catch (_) {
      return const UpdateCheckResult(UpdateCheckStatus.unreachable);
    } finally {
      client.close();
    }
  }

  /// Адрес update.json: в интернете — файл на публичной странице,
  /// у ПК — служебный endpoint синхронизации.
  Uri metaUrl(UpdateSource source) {
    if (source == UpdateSource.web) {
      return Uri.parse('${_normalizeBase(webBaseUrl!)}/update.json');
    }
    return Uri.parse('http://$host/api/v1/update');
  }

  /// Адрес файла: в интернете файл лежит в последнем релизе, у ПК — в
  /// папке раздачи. Токен на ПК по-прежнему нужен, в интернете — нет.
  Uri fileUrl(UpdateSource source, String filename) {
    final name = _safeName(filename);
    if (source == UpdateSource.web) {
      final base = webFileBaseUrl ?? webBaseUrl;
      if (base == null || base.trim().isEmpty) {
        throw StateError('Не задан адрес файлов обновления в интернете');
      }
      return Uri.parse('${_normalizeBase(base)}/$name');
    }
    return Uri.parse('http://$host/files/$name');
  }

  static String _normalizeBase(String raw) {
    var v = raw.trim();
    while (v.endsWith('/') && v.isNotEmpty) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// Скачивает файл обновления в [targetDir] из [source] (по умолчанию —
  /// ПК, как раньше). Если задан [expectedSha256], файл проверяется по
  /// SHA-256 и при несовпадении удаляется. [onProgress] вызывается с
  /// (получено байт, всего байт); всего = 0, если сервер не сообщил длину.
  Future<File> download(
    String filename,
    Directory targetDir, {
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
    UpdateSource source = UpdateSource.pc,
  }) async {
    final file = File(
      '${targetDir.path}${Platform.pathSeparator}${_safeName(filename)}',
    );
    final client = _client();
    try {
      final req = await client.getUrl(fileUrl(source, filename));
      if (source == UpdateSource.pc) _authHeaders().forEach(req.headers.set);
      final res = await req.close().timeout(responseTimeout);
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final total = res.contentLength > 0 ? res.contentLength : 0;
      final sink = file.openWrite();
      var received = 0;
      try {
        // Сервер мог принять соединение и перестать слать куски — без
        // таймаута на простои витрина загрузки висела бы десятки минут.
        await for (final chunk in res.timeout(stallTimeout)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      final expected = expectedSha256?.trim().toLowerCase();
      if (expected != null && expected.isNotEmpty) {
        final bytes = await file.readAsBytes();
        final actual = sha256.convert(bytes).toString();
        if (actual != expected) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          throw HttpException('checksum_mismatch');
        }
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

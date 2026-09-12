import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/note.dart';
import '../models/task.dart';
import 'obsidian_service.dart';
import 'releases.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';
import 'task_database.dart';

/// Результат одной синхронизации сервера.
class SyncServerResult {
  final int addedTasks;
  final int updatedTasks;
  final int addedNotes;
  final int updatedNotes;
  final int obsidianWritten;

  const SyncServerResult({
    this.addedTasks = 0,
    this.updatedTasks = 0,
    this.addedNotes = 0,
    this.updatedNotes = 0,
    this.obsidianWritten = 0,
  });
}

/// Ключ доступа к синку может прятаться и настраиваться автоматически,
/// поэтому сервер держит его в файле рядом с БД. Ротация токена (#19):
/// ПК периодически меняет ключ; старый принимается ещё 3 дня, чтобы
/// телефон, который уже получил новый ключ в шифрованном ответе (или ещё
/// не синкался), не был отрезан.
class SyncServerState {
  static const rotateEveryMs = Duration.millisecondsPerDay;
  static const previousGraceMs = Duration.millisecondsPerDay * 3;

  final File _file;
  Map<String, dynamic> _data;

  SyncServerState._(this._file, this._data);

  /// Каталог состояния сервера. Тесты отключают стабильный путь, чтобы не
  /// трогать реальные данные приложения.
  static String dataDir() {
    if (!TaskDatabase.useStableDesktopPath) {
      return p.join(Directory.current.path, '.khs-data');
    }
    return TaskDatabase.desktopDataDir();
  }

  /// Файл состояния сервера (ключ, счётчики anti-replay, deviceId).
  static String stateFile() => p.join(dataDir(), 'server-state.json');

  static Future<SyncServerState> load(String seedToken) async {
    final file = File(stateFile());
    Map<String, dynamic>? data;
    try {
      if (await file.exists()) {
        final raw = (await file.readAsString()).trim();
        if (raw.isNotEmpty) data = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}
    data ??= {};
    final token = (data['token'] as String? ?? '').trim();
    final seed = seedToken.trim();
    // Ручная смена ключа в настройках ПК имеет приоритет над сохранённым —
    // начинаем с него и забываем старую пару (grace обнуляется).
    if (seed.isNotEmpty && (token.isEmpty || seed != token)) {
      data['token'] = seed;
      data['previous_token'] = null;
      data['previous_token_expiry'] = null;
    }
    data['device_id'] ??= TaskDatabase.newKey();
    data['ctrs'] = Map<String, dynamic>.from(data['ctrs'] as Map? ?? {});
    data['sctr'] = data['sctr'] as int? ?? 0;
    data['last_rotate_at'] = data['last_rotate_at'] as int? ?? 0;
    final state = SyncServerState._(file, data);
    await state.save();
    return state;
  }

  Future<void> save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(_data));
    } catch (_) {}
  }

  String get deviceId => (_data['device_id'] as String?) ?? '';
  String get token => (_data['token'] as String?) ?? '';
  int get sctr => _data['sctr'] as int? ?? 0;

  /// Увеличивает серверный счётчик ответов и возвращает новое значение.
  int nextSctr() {
    final n = (_data['sctr'] as int? ?? 0) + 1;
    _data['sctr'] = n;
    return n;
  }

  /// Текущий ключ и старый (пока не истёк grace-период) — для приёма.
  List<String> acceptedTokens(int nowMs) {
    final result = <String>[];
    final cur = token;
    if (cur.isNotEmpty) result.add(cur);
    final prev = _data['previous_token'] as String?;
    final expiry = _data['previous_token_expiry'] as int?;
    if (prev != null &&
        prev.trim().isNotEmpty &&
        expiry != null &&
        nowMs < expiry) {
      result.add(prev.trim());
    }
    return result;
  }

  /// Проверка накопленного ответа телефона на replay (#6): отклоняем запрос,
  /// если его счётчик не больше уже принятого для этого устройства.
  bool acceptClientCtr(String clientId, int ctr) {
    final map = _data['ctrs'] as Map<String, dynamic>;
    final last = (map[clientId] as int?) ?? 0;
    if (ctr <= last) return false;
    map[clientId] = ctr;
    return true;
  }

  Future<String?> maybeRotate(int nowMs) async {
    final last = _data['last_rotate_at'] as int? ?? 0;
    if (nowMs - last < rotateEveryMs) return null;
    final cur = token;
    if (cur.isEmpty) return null;
    final next = TaskDatabase.newKey();
    if (next.isEmpty || next == cur) return null;
    _data['previous_token'] = cur;
    _data['previous_token_expiry'] = nowMs + previousGraceMs;
    _data['token'] = next;
    _data['last_rotate_at'] = nowMs;
    await save();
    return next;
  }
}

/// HTTP-сервер, который работает в KHS на ПК и отдаёт хранилище
/// (БД + Obsidian) телефону по локальной сети.
class SyncServer {
  final TaskDatabase db;
  final ObsidianService obsidian;
  final int port;

  /// IP-интерфейс для приёма соединений. Пустая строка = любой (0.0.0.0).
  final String bindHost;

  /// Вызывается после того, как данные изменились — чтобы UI обновился.
  final Future<void> Function() onChanged;

  /// Вызывается, когда сервер автоматически сменил ключ доступа (#19).
  final Future<void> Function(String newToken)? onTokenRotated;

  /// Ключ доступа, заданный пользователем/приложением при старте сервера.
  final String token;

  SyncServerState? _state;
  SyncServerState get state => _state!;

  HttpServer? _server;
  bool _running = false;

  static const _maxSyncBody = 16 * 1024 * 1024;
  static const _maxItems = 20000;
  static const _maxQueueDepth = 4;
  Future<void> _syncQueue = Future.value();
  int _queueDepth = 0;

  SyncServer({
    required this.db,
    required this.obsidian,
    required this.port,
    required this.token,
    this.bindHost = '',
    required this.onChanged,
    this.onTokenRotated,
  });

  bool get isRunning => _running;

  /// Локальные IPv4-адреса, по которым телефон может подключиться.
  static Future<List<String>> localAddresses() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) result.add(addr.address);
        }
      }
    } catch (_) {}
    return result;
  }

  Future<void> start() async {
    if (_running) return;
    _state = await SyncServerState.load(token);
    InternetAddress address = InternetAddress.anyIPv4;
    final host = bindHost.trim();
    if (host.isNotEmpty && host != '0.0.0.0') {
      try {
        address = InternetAddress(host);
      } catch (_) {
        address = InternetAddress.anyIPv4;
      }
    }
    final server = await HttpServer.bind(address, port);
    _server = server;
    _running = true;
    server.listen(_handle);
  }

  /// Выбирает «самый подходящий» локальный IP для привязки сервера:
  /// приватный IPv4, не виртуальный адаптер. Если не выйдет — null (любой).
  static Future<String?> preferredBindHost() async {
    try {
      const virtualNames = [
        'loopback',
        'virtualbox',
        'vmware',
        'hyper-v',
        'wsl',
        'tailscale',
        'zerotier',
        'docker',
        'npcap',
        'bluetooth',
        'wireguard',
        'vethernet',
        'hamachi',
      ];
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      String? firstPrivate;
      for (final ni in interfaces) {
        final name = ni.name.toLowerCase();
        if (virtualNames.any((v) => name.contains(v))) continue;
        for (final addr in ni.addresses) {
          if (addr.isLoopback) continue;
          if (addr.isLinkLocal) continue;
          final parts = addr.address.split('.');
          final a = int.tryParse(parts[0]) ?? 0;
          final b = int.tryParse(parts[1]) ?? 0;
          final private = a == 10 ||
              (a == 172 && b >= 16 && b <= 31) ||
              (a == 192 && b == 168);
          if (private) return addr.address;
          firstPrivate ??= addr.address;
        }
      }
      return firstPrivate;
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    _running = false;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      await _logRequest('${req.method} $path');
      if (path == '/api/v1/health' && req.method == 'GET') {
        await _handleHealth(req);
        return;
      }
      if (path == '/api/v1/sync' && req.method == 'POST') {
        if (_queueDepth >= _maxQueueDepth) {
          await _respondJson(req, 429, {'error': 'busy'});
          return;
        }
        await _enqueueSync(() => _handleSync(req));
        return;
      }
      if (path == '/api/v1/update' && req.method == 'GET') {
        await _handleUpdate(req);
        return;
      }
      if ((path == '/' || path == '/index.html') && req.method == 'GET') {
        await _handlePromo(req);
        return;
      }
      if (path.startsWith('/files/') && req.method == 'GET') {
        await _handleFile(req);
        return;
      }
      await _logRequest('-> 404 fallback: $path');
      await _respondJson(req, 404, {'error': 'not_found'});
    } catch (e) {
      try {
        await _logRequest('-> 500: $e');
        await _respondJson(req, 500, {'error': 'internal', 'detail': '$e'});
      } catch (_) {}
    }
  }

  Future<void> _enqueueSync(Future<void> Function() task) {
    _queueDepth++;
    final result = _syncQueue.then((_) => task()).whenComplete(() {
      _queueDepth--;
    });
    _syncQueue = result.catchError((_) {});
    return result;
  }

  /// Журнал запросов для отладки обновлений (рядом с базой данных).
  static File _logFile() => File(p.join(SyncServerState.dataDir(), 'server.log'));

  static Future<void> _logRequest(String line) async {
    try {
      final clean = line.replaceAll(RegExp(r'[\r\n]'), ' ');
      final file = _logFile();
      if (await file.exists() && await file.length() > 5 * 1024 * 1024) {
        try {
          await file.delete();
        } catch (_) {}
      }
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} $clean\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  /// Папки, где ПК ищет обновления (update.json + файлы): рядом с приложением
  /// (где лежит exe), рядом с рабочим каталогом и в папке данных.
  static List<Directory> updateDirs() {
    final seen = <String>{};
    final result = <Directory>[];
    final candidates = <String>[
      if (Platform.resolvedExecutable.isNotEmpty)
        p.dirname(Platform.resolvedExecutable),
      Directory.current.path,
      TaskDatabase.desktopDataDir(),
    ];
    for (final base in candidates) {
      final key = Directory(base).absolute.path;
      if (seen.add(key)) result.add(Directory(p.join(base, 'updates')));
    }
    return result;
  }

  File? _findUpdateFile(String name) {
    if (name.isEmpty) return null;
    for (final dir in updateDirs()) {
      final file = File(p.join(dir.path, name));
      if (file.existsSync()) return file;
    }
    return null;
  }

  Future<({File file, Map<String, dynamic> meta})?> _findUpdateMeta() async {
    final file = _findUpdateFile('update.json');
    if (file == null) return null;
    try {
      var text = await file.readAsString();
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      final meta = jsonDecode(text) as Map<String, dynamic>;
      return (file: file, meta: meta);
    } catch (_) {
      return null;
    }
  }

  /// Разрешённые к отдаче по /files/ имена (#17): файлы обновлений из
  /// update.json + index.html — все строго из каталога этого update.json.
  Set<String> _allowedFileNames(Map<String, dynamic> meta) {
    final names = <String>{'index.html'};
    for (final key in ['android', 'windows']) {
      final v = meta[key] as String?;
      if (v != null && v.trim().isNotEmpty) {
        names.add(p.basename(v.trim()));
      }
    }
    return names;
  }

  /// GET / — промо-страница приложения (index.html рядом с update.json).
  Future<void> _handlePromo(HttpRequest req) async {
    final file = _findUpdateFile('index.html');
    if (file == null || !file.existsSync()) {
      await _respondJson(req, 404, {'error': 'not_found'});
      return;
    }
    final bytes = await file.readAsBytes();
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..contentLength = bytes.length;
    req.response.add(bytes);
    await req.response.close();
  }

  /// GET /api/v1/health — диспетчер отвечает «жив/не жив», но только
  /// тому, кто знает ключ (#18): без аутентификации не светим даже это.
  Future<void> _handleHealth(HttpRequest req) async {
    final key = 'health:${_remote(req)}';
    if (_tokenRateBlocked(key)) {
      await _respondJson(req, 403, {'error': 'too_many_failures'});
      return;
    }
    final token = _sentToken(req);
    if (!_tokenOkForNetwork(token, DateTime.now().millisecondsSinceEpoch)) {
      _tokenFailure(key);
      await _respondJson(req, 401, {'error': 'unauthorized'});
      return;
    }
    _tokenSuccess(key);
    await _respondJson(req, 200, {'ok': true});
  }

  /// Проверяет ключ (текущий или из grace-периода) — константное время.
  bool _tokenOkForNetwork(String? sent, int nowMs) {
    final accepted = state.acceptedTokens(nowMs);
    if (accepted.isEmpty) return false;
    if (sent == null) return false;
    for (final t in accepted) {
      if (sent.length != t.length) continue;
      var diff = 0;
      for (var i = 0; i < t.length; i++) {
        diff |= t.codeUnitAt(i) ^ sent.codeUnitAt(i);
      }
      if (diff == 0) return true;
    }
    return false;
  }

  /// GET /api/v1/update — метаданные доступного обновления (из update.json).
  Future<void> _handleUpdate(HttpRequest req) async {
    final key = 'update:${_remote(req)}';
    if (_tokenRateBlocked(key)) {
      await _respondJson(req, 403, {'error': 'too_many_failures'});
      return;
    }
    final token = _sentToken(req);
    if (!_tokenOkForNetwork(token, DateTime.now().millisecondsSinceEpoch)) {
      _tokenFailure(key);
      await _respondJson(req, 401, {'error': 'unauthorized'});
      return;
    }
    _tokenSuccess(key);
    final found = await _findUpdateMeta();
    if (found == null) {
      await _respondJson(req, 404, {'error': 'no_update'});
      return;
    }
    final meta = found.meta;
    final result = <String, dynamic>{
      'version': meta['version'] as String? ?? '',
      'notes': meta['notes'] as String? ?? '',
      'history': [
        for (final r in khsReleases)
          {
            'version': r.version,
            'date': r.date,
            'changes': [for (final c in r.changes) c.text],
          },
      ],
    };
    final signature = meta['signature'] as String?;
    if (signature != null && signature.trim().isNotEmpty) {
      result['signature'] = signature.trim();
    }
    for (final key in ['android', 'windows']) {
      final name = meta[key] as String?;
      if (name == null) continue;
      final f = File(p.join(found.file.parent.path, p.basename(name.trim())));
      if (f.existsSync()) {
        result[key] = name.trim();
        result['${key}_size'] = f.lengthSync();
        final sha = meta['${key}_sha256'] as String?;
        if (sha != null && sha.trim().isNotEmpty) {
          result['${key}_sha256'] = sha.trim().toLowerCase();
        }
      }
    }
    await _respondJson(req, 200, result);
  }

  /// GET /files/{name} — отдача файла обновления, только из allowlist (#17).
  Future<void> _handleFile(HttpRequest req) async {
    final name = req.uri.pathSegments.last;
    if (name.isEmpty ||
        name.contains('..') ||
        name.contains('/') ||
        name.contains(r'\')) {
      await _respondJson(req, 400, {'error': 'bad_name'});
      return;
    }
    final key = 'files:${_remote(req)}';
    if (_tokenRateBlocked(key)) {
      await _respondJson(req, 403, {'error': 'too_many_failures'});
      return;
    }
    final token = _sentToken(req);
    if (!_tokenOkForNetwork(token, DateTime.now().millisecondsSinceEpoch)) {
      _tokenFailure(key);
      await _respondJson(req, 401, {'error': 'unauthorized'});
      return;
    }
    _tokenSuccess(key);
    final found = await _findUpdateMeta();
    if (found == null) {
      await _respondJson(req, 404, {'error': 'not_found'});
      return;
    }
    final allowed = _allowedFileNames(found.meta);
    late final File? file;
    if (allowed.contains(p.basename(name))) {
      final f = File(p.join(found.file.parent.path, p.basename(name)));
      file = f.existsSync() ? f : null;
      if (file == null) {
        // Совместимость со старыми клиентами: битый клиент просил «мусорное»
        // имя — отдаём актуальный android-файл из update.json.
        final fallback = await _brokenClientFallback(found);
        if (fallback != null) {
          await _logRequest(
            '-> fallback for "$name" -> ${p.basename(fallback.path)}',
          );
          return await _streamFile(req, fallback);
        }
        await _logRequest('-> 404 file: "$name" not found');
        await _respondJson(req, 404, {'error': 'not_found'});
        return;
      }
    } else {
      await _logRequest('-> 403 file: "$name" not allowed');
      await _respondJson(req, 403, {'error': 'not_allowed'});
      return;
    }
    await _logRequest('-> 200 file: ${p.basename(name)} (${file.lengthSync()} b)');
    await _streamFile(req, file);
  }

  /// Если запрошенное имя — «мусорное» из-за бага интерполяции в старом
  /// клиенте, возвращает текущий файл обновления для Android.
  Future<File?> _brokenClientFallback(
    ({File file, Map<String, dynamic> meta}) found,
  ) async {
    final name = p.basename(found.file.path);
    if (!name.contains('Closure') && !name.contains('Function') && !name.contains('(filename)')) {
      return null;
    }
    final fileName = found.meta['android'] as String?;
    if (fileName == null) return null;
    final f = File(p.join(found.file.parent.path, p.basename(fileName)));
    return f.existsSync() ? f : null;
  }

  Future<void> _streamFile(HttpRequest req, File file) async {
    final size = file.lengthSync();
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.binary
      ..contentLength = size;
    try {
      await req.response.addStream(file.openRead());
    } finally {
      await req.response.close();
    }
  }

  /// Защита от перебора токена: после нескольких неудач подряд ответы с 401
  /// прекращаются на 60 секунд для этого источника.
  static const _maxTokenFails = 6;
  final _tokenFails = <String, int>{};
  DateTime? _blockedUntil;

  bool _tokenRateBlocked(String key) {
    final now = DateTime.now();
    if (_blockedUntil != null && now.isBefore(_blockedUntil!)) return true;
    if (_blockedUntil != null) {
      _blockedUntil = null;
      _tokenFails.clear();
    }
    return (_tokenFails[key] ?? 0) >= _maxTokenFails;
  }

  void _tokenFailure(String key) {
    _tokenFails[key] = (_tokenFails[key] ?? 0) + 1;
    if (_tokenFails[key]! >= _maxTokenFails) {
      _blockedUntil = DateTime.now().add(const Duration(seconds: 60));
    }
  }

  void _tokenSuccess(String key) {
    _tokenFails.remove(key);
    _blockedUntil = null;
  }

  static String _remote(HttpRequest req) =>
      req.connectionInfo?.remoteAddress.address ?? '?';

  String? _sentToken(HttpRequest req) {
    final header = req.headers.value('X-KHS-Token');
    if (header != null && header.trim().isNotEmpty) return header.trim();
    return null;
  }

  Future<String?> _readBodyCapped(HttpRequest req) async {
    final buffer = StringBuffer();
    var size = 0;
    await for (final chunk in utf8.decoder.bind(req)) {
      buffer.write(chunk);
      size += chunk.length;
      if (size > _maxSyncBody) return null;
    }
    return buffer.toString();
  }

  Future<void> _handleSync(HttpRequest req) async {
    final raw = await _readBodyCapped(req);
    if (raw == null) {
      await _respondJson(req, 413, {'error': 'too_large'});
      return;
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await _respondJson(req, 400, {'error': 'bad_json'});
      return;
    }

    final syncKey = 'sync:${_remote(req)}';
    if (_tokenRateBlocked(syncKey)) {
      await _respondJson(req, 403, {'error': 'too_many_failures'});
      return;
    }
    if ((body['v'] as int?) != 2) {
      await _respondJson(req, 426, {'error': 'protocol_old'});
      return;
    }
    final dataB64 = body['data'] as String?;
    if (dataB64 == null || dataB64.isEmpty) {
      await _respondJson(req, 400, {'error': 'bad_body'});
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final acceptedTokens = state.acceptedTokens(nowMs);
    Map<String, dynamic> inner = const {};
    var ok = false;
    String? authToken;
    for (final t in acceptedTokens) {
      try {
        final decoded =
            jsonDecode(await SyncCrypto.decrypt(t, dataB64));
        if (decoded is Map<String, dynamic>) {
          inner = decoded;
          authToken = t;
          ok = true;
          break;
        }
      } catch (_) {}
    }
    if (!ok || authToken == null) {
      _tokenFailure(syncKey);
      await _respondJson(req, 401, {'error': 'unauthorized'});
      return;
    }
    _tokenSuccess(syncKey);

    // Anti-replay (#6): счётчик устройства из зашифрованного тела. Если
    // перехваченный запрос повторить — счётчик не больше принятого,
    // и запрос отклоняется ДО применения изменений.
    final clientId = inner['cid'] as String?;
    final ctr = inner['ctr'];
    if (clientId == null || clientId.length > 64) {
      await _respondJson(req, 400, {'error': 'bad_client'});
      return;
    }
    final ctrInt = ctr is int ? ctr : null;
    if (ctrInt == null || ctrInt < 0) {
      await _respondJson(req, 400, {'error': 'bad_ctr'});
      return;
    }

    final clientTasks = (inner['tasks'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final clientNotes = (inner['notes'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (clientTasks.length > _maxItems || clientNotes.length > _maxItems) {
      await _respondJson(req, 413, {'error': 'too_many_items'});
      return;
    }

    // Anti-replay (#6): счётчик устройства из зашифрованного тела. Если
    // перехваченный запрос повторить — счётчик не больше принятого,
    // и запрос отклоняется ДО применения изменений.
    if (!state.acceptClientCtr(clientId, ctrInt)) {
      await _logRequest('-> 409 replay: $clientId ctr=$ctrInt');
      await _respondJson(req, 409, {'error': 'replay'});
      return;
    }

    final serverTasks = await db.getAllTasks();
    final serverNotes = await db.getAllNotes();

    final mergedTasks = SyncEngine.mergeTasks(serverTasks, clientTasks, now: nowMs);
    final mergedNotes = SyncEngine.mergeNotes(serverNotes, clientNotes, now: nowMs);

    var addedTasks = 0;
    var updatedTasks = 0;
    var addedNotes = 0;
    var updatedNotes = 0;
    var obsidianWritten = 0;

    final serverTaskByKey = {
      for (final r in serverTasks)
        if (r['client_key'] is String) r['client_key'] as String: r,
    };
    final serverNoteByKey = {
      for (final r in serverNotes)
        if (r['client_key'] is String) r['client_key'] as String: r,
    };

    for (final row in mergedTasks) {
      final key = row['client_key'];
      if (key is! String) continue;
      final existing = serverTaskByKey[key];
      if (existing == null) {
        await db.insertTask(Task.fromMap(SyncEngine.withoutId(row)));
        addedTasks++;
      } else {
        final winner = SyncEngine.newerTask(existing, row);
        if (identical(winner, row) || !_sameContent(existing, row)) {
          final withId = Map<String, dynamic>.from(row)
            ..['id'] = existing['id'];
          await db.updateTask(Task.fromMap(withId), bumpUpdatedAt: false);
          updatedTasks++;
        }
      }
    }

    for (final row in mergedNotes) {
      final key = row['client_key'];
      if (key is! String) continue;
      final existing = serverNoteByKey[key];
      if (existing == null) {
        await db.insertNote(Note.fromMap(SyncEngine.withoutId(row)));
        addedNotes++;
      } else {
        final winner = SyncEngine.newerNote(existing, row);
        if (identical(winner, row) || !_sameContent(existing, row)) {
          final withId = Map<String, dynamic>.from(row)
            ..['id'] = existing['id'];
          await db.updateNote(Note.fromMap(withId));
          updatedNotes++;
        }
      }
    }

    // Пишем в Obsidian заметки, которые пришли с телефона: ежедневные — в
    // блок ежедневной заметки (включая удаления — очищаем блок), отдельные
    // заметки без даты — отдельными файлами в папке «заметки».
    for (final row in clientNotes) {
      if (!obsidian.isConfigured) break;
      final dateMs = row['note_date'];
      final note = Note.fromMap(row);
      if (dateMs is! int) {
        try {
          if (note.deleted) {
            await obsidian.deleteStandaloneNote(note);
          } else {
            await obsidian.writeStandaloneNote(note);
          }
          obsidianWritten++;
        } catch (_) {}
        continue;
      }
      final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
      if (note.deleted) {
        try {
          await obsidian.writeDailyNote(date, body: '');
          obsidianWritten++;
        } catch (_) {}
      } else {
        final tasks = _tasksForDate(mergedTasks, date);
        try {
          await obsidian.writeDailyNote(date, body: note.content, tasks: tasks);
          obsidianWritten++;
        } catch (_) {}
      }
    }

    final changed =
        addedTasks > 0 ||
        updatedTasks > 0 ||
        addedNotes > 0 ||
        updatedNotes > 0;
    if (changed) {
      await onChanged();
    }

    // Ротация ключа (#19): новый ключ передаётся ТОЛЬКО в шифрованном
    // ответе и применяется при следующем синке; старый живёт ещё 3 дня.
    final newToken = await state.maybeRotate(nowMs);
    if (newToken != null) {
      try {
        await onTokenRotated?.call(newToken);
      } catch (_) {}
    }
    final sctr = state.nextSctr();
    await state.save();

    final reply = {
      'tasks': mergedTasks,
      'notes': mergedNotes,
      'vaultPath': obsidian.vaultPath,
      'time': nowMs,
      'deviceId': state.deviceId,
      'sctr': sctr,
      if (newToken != null) 'newToken': newToken,
    };
    final data = await SyncCrypto.encrypt(authToken, jsonEncode(reply));
    await _respondJson(req, 200, {'v': 2, 'data': data});

    _lastResult = SyncServerResult(
      addedTasks: addedTasks,
      updatedTasks: updatedTasks,
      addedNotes: addedNotes,
      updatedNotes: updatedNotes,
      obsidianWritten: obsidianWritten,
    );
  }

  SyncServerResult? _lastResult;
  SyncServerResult? get lastResult => _lastResult;

  static bool _sameContent(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  static List<Task> _tasksForDate(
    List<Map<String, dynamic>> rows,
    DateTime date,
  ) {
    return rows
        .where((r) => (r['deleted'] as int? ?? 0) == 0)
        .map(Task.fromMap)
        .where((t) {
          final due = t.dueAt;
          return due != null &&
              due.year == date.year &&
              due.month == date.month &&
              due.day == date.day;
        })
        .toList();
  }

  Future<void> _respondJson(HttpRequest req, int status, Object body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }
}
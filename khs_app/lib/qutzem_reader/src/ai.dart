import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

enum AiProvider { openrouter, ollama, gemini, groq, free }

extension AiProviderInfo on AiProvider {
  String get label {
    switch (this) {
      case AiProvider.openrouter:
        return 'OpenRouter';
      case AiProvider.ollama:
        return 'Ollama (локально)';
      case AiProvider.gemini:
        return 'Gemini';
      case AiProvider.groq:
        return 'Groq';
      case AiProvider.free:
        return 'Бесплатно (интернет)';
    }
  }

  String get baseUrl {
    switch (this) {
      case AiProvider.openrouter:
        return 'https://openrouter.ai/api/v1';
      case AiProvider.ollama:
        return 'http://localhost:11434/v1';
      case AiProvider.gemini:
        return 'https://generativelanguage.googleapis.com/v1beta/openai';
      case AiProvider.groq:
        return 'https://api.groq.com/openai/v1';
      case AiProvider.free:
        return 'https://text.pollinations.ai';
    }
  }

  String get defaultModel {
    switch (this) {
      case AiProvider.openrouter:
        return 'gpt-4o-mini';
      case AiProvider.ollama:
        return 'llama3.2';
      case AiProvider.gemini:
        return 'gemini-2.0-flash';
      case AiProvider.groq:
        return 'llama-3.3-70b-versatile';
      case AiProvider.free:
        return 'openai';
    }
  }

  bool get needsKey {
    switch (this) {
      case AiProvider.ollama:
      case AiProvider.free:
        return false;
      default:
        return true;
    }
  }

  /// Умеет ли провайдер принимать картинки. Нужно для распознавания текста
  /// со снимка страницы: обычный запрос к модели умеет только текст.
  ///
  ///ollama и «Бесплатно (интернет)» помечены как не умеющие: у Ollama всё
  /// зависит от скачанной модели, а pollinations картинки не принимает вовсе.
  bool get supportsVision {
    switch (this) {
      case AiProvider.openrouter:
      case AiProvider.gemini:
      case AiProvider.groq:
        return true;
      case AiProvider.ollama:
      case AiProvider.free:
        return false;
    }
  }

  /// Модель, которая заведомо читает картинки — подсказка для пользователя,
  /// если выбранная модель текстовая и сервер ответил отказом.
  String get visionModelHint {
    switch (this) {
      case AiProvider.gemini:
        return 'gemini-2.0-flash';
      case AiProvider.openrouter:
        return 'google/gemini-2.0-flash-001';
      case AiProvider.groq:
        return 'meta-llama/llama-4-scout-17b-16e-instruct';
      case AiProvider.ollama:
      case AiProvider.free:
        return '';
    }
  }
}

class AnalysisContext {
  final String bookTitle;
  final String bookAuthor;
  final String chapter;

  const AnalysisContext({
    this.bookTitle = '',
    this.bookAuthor = '',
    this.chapter = '',
  });
}

/// Что именно спрашивает пользователя.
enum AiPromptKind {
  analysis,

  /// «Что значит термин».
  explainTerm,

  /// «Опиши этот отрывок»: кто, где, о чём, без догадок.
  passageDescription,

  /// «Краткий пересказ» в несколько строк.
  briefSummary,

  /// Определить книгу по фрагменту.
  identifyBook,
}

class AiSettings {
  AiProvider provider;
  String apiKey;
  String baseUrl;
  String model;

  AiSettings({
    this.provider = AiProvider.openrouter,
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
  });

  void normalize() {
    if (baseUrl.trim().isEmpty) {
      baseUrl = provider.baseUrl;
    }
    if (model.trim().isEmpty) {
      model = provider.defaultModel;
    }
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'model': model,
  };

  factory AiSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return AiSettings();
    final settings = AiSettings(
      provider: AiProvider.values.firstWhere(
        (e) => e.name == json['provider'],
        orElse: () => AiProvider.openrouter,
      ),
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
    );
    settings.normalize();
    return settings;
  }
}

class AiService {
  AiSettings settings;

  AiService(this.settings);

  /// Без ключа: сначала локальная Ollama (оффлайн), затем бесплатный
  /// облачный endpoint (работает и на телефоне, через интернет).
  Future<String> _analyzeKeyless(
    String fragment,
    AnalysisContext? ctx,
    AiPromptKind kind,
  ) async {
    final models = await fetchOllamaModels('http://localhost:11434/v1');
    if (models.isNotEmpty) {
      return AiService(
        AiSettings(
          provider: AiProvider.ollama,
          baseUrl: 'http://localhost:11434/v1',
          model: models.first,
        ),
      ).analyzeFragment(fragment, ctx: ctx, kind: kind);
    }
    return AiService(AiSettings(provider: AiProvider.free))
        .analyzeFragment(fragment, ctx: ctx, kind: kind);
  }

  /// Собирает промпт под нужный вид вопроса.
  String _buildPrompt(
    String fragment,
    AnalysisContext? ctx,
    AiPromptKind kind,
  ) {
    final prompt = StringBuffer();
    if (kind == AiPromptKind.explainTerm) {
      prompt.writeln(
        'Ты — толковый словарь и литературный справочник. '
        'Вот термин, фраза или слово из книги.',
      );
    } else if (kind == AiPromptKind.passageDescription) {
      prompt.writeln('Ты — литературовед. Опиши этот отрывок из книги.');
    } else {
      prompt.writeln('Ты — литературный помощник читателя. ');
    }
    if (ctx != null &&
        (ctx.bookTitle.isNotEmpty || ctx.bookAuthor.isNotEmpty)) {
      final src = <String>[
        if (ctx.bookTitle.isNotEmpty) '«${ctx.bookTitle}»',
        if (ctx.bookAuthor.isNotEmpty) ctx.bookAuthor,
      ];
      prompt.write('Источник: ${src.join(', ')}.');
    }
    if (ctx != null && ctx.chapter.isNotEmpty) {
      prompt.writeln(' Глава / раздел: ${ctx.chapter}.');
    } else {
      prompt.writeln();
    }
    if (kind == AiPromptKind.explainTerm) {
      prompt.writeln(
        'Объясни на русском языке, коротко и по делу: '
        'что означает термин «$fragment» в контексте этой книги, '
        'откуда он взялся (устаревшее слово, иностранный/жаргонный оборот, '
        'имя, отсылка, понятие), и что он значит для понимания текста. '
        'Отвечай только по сути вопроса.',
      );
    } else if (kind == AiPromptKind.passageDescription) {
      prompt.writeln(
        'Опиши этот отрывок на русском языке: где происходит действие, '
        'кто из героев в нём участвует и что происходит по сюжету. '
        'Не пересказывай дословно и не выдумывай того, чего в тексте нет. '
        'Ответ — несколько абзацев.',
      );
      prompt.writeln('\nОтрывок:\n---\n$fragment\n---');
    } else if (kind == AiPromptKind.briefSummary) {
      prompt.writeln(
        'Перескажи этот отрывок очень кратко — в трёх-четырёх предложениях, '
        'чтобы было понятно, о чём он, без деталей и без оценок.',
      );
      prompt.writeln('\nОтрывок:\n---\n$fragment\n---');
    } else {
      prompt.writeln(
        'Сделай разбор на русском языке: о чём речь (2-3 предложения), '
        'кто говорит или о ком идёт речь, '
        'ключевые термины / имена / отсылки, '
        'что это значит для сюжета / героя / темы произведения, '
        'и при необходимости поясни сложные места.',
      );
      prompt.writeln('\nФрагмент:\n---\n$fragment\n---');
    }
    return prompt.toString();
  }

  Future<String> analyzeFragment(
    String fragment, {
    AnalysisContext? ctx,
    AiPromptKind kind = AiPromptKind.analysis,
  }) async {
    settings.normalize();
    if (settings.provider.needsKey && settings.apiKey.trim().isEmpty) {
      return _analyzeKeyless(fragment, ctx, kind);
    }
    return _chat(content: _buildPrompt(fragment, ctx, kind));
  }

  /// Распознаёт текст на изображении через зрение модели.
  ///
  /// [imageBytes] — уже сжатая картинка (см. [prepareImageForAi]), [mimeType] —
  /// её тип. Возвращает только сам текст, без рассуждений модели.
  Future<String> recognizeTextFromImage({
    required List<int> imageBytes,
    required String mimeType,
    String? bookHint,
  }) async {
    settings.normalize();
    if (!settings.provider.supportsVision) {
      final hint = settings.provider.visionModelHint;
      throw Exception(
        'Провайдер «${settings.provider.label}» не умеет читать картинки. '
        'Выберите в настройках ИИ провайдера, который умеет'
        '${hint.isEmpty ? '' : ' (например, $hint)'}.',
      );
    }
    if (settings.apiKey.trim().isEmpty) {
      throw Exception(
        'Для распознавания текста нужен API-ключ провайдера. '
        'Откройте настройки ИИ и укажите ключ.',
      );
    }
    final prompt = StringBuffer()
      ..writeln(
        'Считай текст с изображения и выведи только этот текст, '
        'без пояснений и без оформления. Сохрани переносы строк и абзацы.',
      );
    if (bookHint != null && bookHint.trim().isNotEmpty) {
      prompt.writeln(
        'Известно, что страница из книги «${bookHint.trim()}». '
        'Учитывай это при исправлении ошибок распознавания.',
      );
    }
    if (settings.model.trim().isEmpty) {
      prompt.writeln(
        'Это страница старой книги: возможны дореформенная орфография, '
        '«ѣ», «і» и прочие буквы, не восстанавливай их.',
      );
    }
    return _chat(
      temperature: 0,
      content: [
        {'type': 'text', 'text': prompt.toString()},
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:$mimeType;base64,${base64Encode(imageBytes)}',
          },
        },
      ],
    );
  }

  /// Пытается определить книгу по куску текста из неё.
  ///
  /// Возвращает пару (название, автор); любой элемент может оказаться пустым,
  /// если модель не уверена.
  Future<({String title, String author})> identifyBook(
    String fragment, {
    AnalysisContext? ctx,
  }) async {
    settings.normalize();
    final known =
        ctx != null && (ctx.bookTitle.isNotEmpty || ctx.bookAuthor.isNotEmpty);
    if (settings.provider.needsKey &&
        settings.apiKey.trim().isEmpty &&
        !known) {
      // Без ключа определить книгу нечем: идентификация требует эрудиции,
      // а не просто пересказа.
      throw Exception(
        'Чтобы опознать книгу по отрывку, нужен API-ключ ИИ. '
        'Откройте настройки ИИ и укажите ключ — либо впишите название вручную.',
      );
    }
    final prompt = StringBuffer()
      ..writeln(
        'Определи, из какой книги этот отрывок. Ответь строго двумя строками '
        'без пояснений, в виде:\n'
        'НАЗВАНИЕ: ...\nАВТОР: ...\n'
        'Если уверенности нет, всё равно назови наиболее вероятную книгу. '
        'Название и автора пиши по-русски, как их принято упоминать.',
      );
    if (known) {
      prompt.writeln(
        'Читатель уже читает «${ctx.bookTitle}» '
        '${ctx.bookAuthor.isEmpty ? '' : '(автор ${ctx.bookAuthor})'}. '
        'Если отрывок взят из неё — назови именно её.',
      );
    }
    prompt.writeln('\nОтрывок:\n---\n$fragment\n---');
    final raw = await _chat(content: prompt.toString(), temperature: 0);
    return _parseBookIdentity(raw);
  }

  static ({String title, String author}) _parseBookIdentity(String raw) {
    var title = '';
    var author = '';
    for (final line in raw.split('\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      if (value.isEmpty) continue;
      if (title.isEmpty &&
          (key.contains('название') || key.contains('title'))) {
        title = value;
      } else if (author.isEmpty &&
          (key.contains('автор') || key.contains('author'))) {
        author = value;
      }
    }
    if (title.isEmpty && author.isEmpty) {
      // Модель ответила просто текстом — берём первую осмысленную строку.
      final first = raw
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      title = first.replaceAll(RegExp(r'^[*#\s]+'), '');
    }
    return (title: title, author: author);
  }

  /// Общий поход к провайдеру. [content] — либо строка, либо список частей
  /// (текст + картинка в формате OpenAI).
  Future<String> _chat({
    required Object content,
    double temperature = 0.3,
  }) async {
    final body = {
      'model': settings.model,
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'temperature': temperature,
    };
    final url = '${settings.baseUrl}/chat/completions';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (settings.apiKey.isNotEmpty)
        'Authorization': 'Bearer ${settings.apiKey}',
    };
    if (settings.provider == AiProvider.openrouter) {
      headers['HTTP-Referer'] = 'https://qutzem.app';
      headers['X-Title'] = 'QutZem Reader';
    }
    final resp = await http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
    if (resp.statusCode != 200) {
      final body = resp.body.trim();
      final shown = body.length > 400 ? '${body.substring(0, 400)}…' : body;
      if (settings.provider == AiProvider.ollama &&
          body.toLowerCase().contains('not found')) {
        throw Exception(
          "Модель '${settings.model}' не найдена в Ollama. "
          'Установленные модели можно выбрать в настройках → «ИИ-разбор фрагмента».',
        );
      }
      throw Exception('Ошибка ИИ (${resp.statusCode}): $shown');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Нет ответа от модели');
    }
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?;
    return (message?['content'] as String? ?? '').trim();
  }
}

/// Готовит картинку к отправке в ИИ: уменьшает и пережимает в JPEG.
///
/// Снимок с телефона весит несколько мегабайт, а в base64 ещё и растёт
/// примерно на треть — провайдеры начинают отклонять такой запрос. Для
/// распознавания текста хватает 1600px по длинной стороне.
Uint8List prepareImageForAi(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  const maxSide = 1600;
  var image = decoded;
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxSide) {
    image = image.width > image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }
  final encoded = img.encodeJpg(image, quality: 85);
  return Uint8List.fromList(encoded);
}

/// Список моделей из запущенной Ollama (`GET /api/tags`).
///
/// [baseUrl] может быть вида `http://localhost:11434/v1` — корень
/// вычисляется отбрасыванием `/v1`. Если Ollama не запущена или отвечает
/// не по 200, возвращается пустой список.
Future<List<String>> fetchOllamaModels(String baseUrl) async {
  final root = baseUrl.trim().replaceFirst(RegExp(r'/v1/?$'), '');
  try {
    final resp = await http
        .get(Uri.parse('$root/api/tags'))
        .timeout(const Duration(seconds: 3));
    if (resp.statusCode != 200) return const [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final models = data['models'] as List<dynamic>? ?? [];
    return models
        .map(
          (e) => ((e as Map<String, dynamic>)['name'] as String? ?? '').trim(),
        )
        .where((s) => s.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Диалог «Анализ нейросети»: спиннер во время запроса, результат или ошибка.
///
/// [ctx] — контекст книги (название, автор, глава), чтобы разбор был
/// привязан к произведению. [onOpenSettings] — если передан и у службы
/// нет ключа API, в диалоге появляется кнопка «Настроить ИИ».
Future<void> showAiAnalysisDialog(
  BuildContext context,
  AiSettings settings,
  String fragment, {
  AnalysisContext? ctx,
  AiPromptKind kind = AiPromptKind.analysis,
  Future<void> Function()? onOpenSettings,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => _AiAnalysisDialog(
      settings: settings,
      fragment: fragment,
      ctx: ctx,
      kind: kind,
      onOpenSettings: onOpenSettings,
    ),
  );
}

class _AiAnalysisDialog extends StatefulWidget {
  final AiSettings settings;
  final String fragment;
  final AnalysisContext? ctx;
  final AiPromptKind kind;
  final Future<void> Function()? onOpenSettings;

  const _AiAnalysisDialog({
    required this.settings,
    required this.fragment,
    this.ctx,
    this.kind = AiPromptKind.analysis,
    this.onOpenSettings,
  });

  @override
  State<_AiAnalysisDialog> createState() => _AiAnalysisDialogState();
}

class _AiAnalysisDialogState extends State<_AiAnalysisDialog> {
  late final Future<String> _future = AiService(widget.settings)
      .analyzeFragment(widget.fragment, ctx: widget.ctx, kind: widget.kind);

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final sourceParts = <String>[
      if (ctx != null && ctx.bookTitle.isNotEmpty) ctx.bookTitle,
      if (ctx != null && ctx.bookAuthor.isNotEmpty) ctx.bookAuthor,
      if (ctx != null && ctx.chapter.isNotEmpty) ctx.chapter,
    ];
    final isTerm = widget.kind == AiPromptKind.explainTerm;
    final isDescription = widget.kind == AiPromptKind.passageDescription;
    final isSummary = widget.kind == AiPromptKind.briefSummary;
    final title = isTerm
        ? 'Что значит термин'
        : isDescription
        ? 'Описание отрывка'
        : isSummary
        ? 'Краткий пересказ'
        : 'Анализ нейросети';
    final icon = isTerm
        ? Icons.menu_book
        : isDescription
        ? Icons.auto_stories_outlined
        : isSummary
        ? Icons.short_text
        : Icons.psychology;
    final busyText = isTerm
        ? 'Смотрю значение термина…'
        : isDescription
        ? 'Описываю отрывок…'
        : isSummary
        ? 'Пересказываю…'
        : 'Анализирую фрагмент…';
    return AlertDialog(
      title: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          const Spacer(),
          if (sourceParts.isNotEmpty)
            Flexible(
              child: Text(
                sourceParts.join(' · '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: FutureBuilder<String>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(busyText),
                  ],
                ),
              );
            }
            final error = snapshot.error;
            if (error != null || !snapshot.hasData) {
              final msg = '$error';
              if (msg.contains('Не задан ключ API')) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Для анализа фрагмента нужен ключ API провайдера.',
                      style: TextStyle(color: Color(0xFFB00020)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Откройте «Настройки → ИИ-разбор фрагмента», '
                      'выберите провайдера и введите API-ключ.\n\n'
                      'Или обойдётесь без ключа: провайдер «Бесплатно '
                      '(интернет)» работает через интернет, а «Ollama '
                      '(локально)» — установите Ollama, и модель будет '
                      'работать даже без интернета.',
                      style: TextStyle(fontSize: 13),
                    ),
                    if (widget.onOpenSettings != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          await widget.onOpenSettings!();
                          if (mounted) navigator.pop();
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('Настроить ИИ'),
                      ),
                    ],
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Не удалось выполнить анализ:\n$error\n\n'
                    'Проверьте настройки нейросети (раздел «ИИ» в настройках), '
                    'запущена ли Ollama, и интернет.',
                    style: const TextStyle(color: Color(0xFFB00020)),
                  ),
                  if (widget.onOpenSettings != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        await widget.onOpenSettings!();
                        if (mounted) navigator.pop();
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Настроить ИИ'),
                    ),
                  ],
                ],
              );
            }
            return SingleChildScrollView(child: SelectableText(snapshot.data!));
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

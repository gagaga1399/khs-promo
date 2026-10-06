import 'package:flutter/material.dart';

import '../../../ui/settings_kit.dart';
import '../ai.dart';
import '../search.dart';
import '../settings.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _syncCtrl;
  late final TextEditingController _aiModelCtrl;
  late final TextEditingController _aiKeyCtrl;
  late final TextEditingController _aiUrlCtrl;
  late AppSettings _s;
  List<String> _ollamaModels = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _s = AppSettings.fromJson(widget.settings.toJson());
    _nameCtrl = TextEditingController(text: _s.displayName);
    _syncCtrl = TextEditingController(text: _s.syncServer);
    _aiModelCtrl = TextEditingController(text: _s.ai.model);
    _aiKeyCtrl = TextEditingController(text: _s.ai.apiKey);
    _aiUrlCtrl = TextEditingController(text: _s.ai.baseUrl);
    if (_s.ai.provider == AiProvider.ollama) {
      _reloadOllamaModels();
    }
  }

  /// Спрашивает запущенную Ollama, какие модели установлены, и, если текущая
  /// модель не найдена, подставляет первую доступную.
  Future<void> _reloadOllamaModels() async {
    final base = _s.ai.baseUrl.trim().isEmpty
        ? AiProvider.ollama.baseUrl
        : _s.ai.baseUrl;
    final models = await fetchOllamaModels(base);
    if (!mounted) return;
    setState(() {
      _ollamaModels = models;
      if (_ollamaModels.isNotEmpty && !_ollamaModels.contains(_s.ai.model)) {
        _s.ai.model = _ollamaModels.first;
        _aiModelCtrl.text = _s.ai.model;
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _syncCtrl.dispose();
    _aiModelCtrl.dispose();
    _aiKeyCtrl.dispose();
    _aiUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _s.displayName = _nameCtrl.text.trim();
    _s.syncServer = _syncCtrl.text.trim();
    await SettingsStore.instance.save(_s);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
      Navigator.pop(context);
    }
  }

  /// Группа видна, если запрос пуст или совпал с её названием либо с одним из
  /// пунктов. Ищет без учёта регистра и «ё».
  bool _visible(List<String> haystack) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase().replaceAll('ё', 'е');
    for (final raw in haystack) {
      final h = raw.toLowerCase().replaceAll('ё', 'е');
      if (h.contains(q)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final muted = SettingsTokens.muted(context);
    final children = <Widget>[];

    if (_visible(['Профиль', 'Имя для синхронизации', 'Адрес сервера'])) {
      children.add(
        SettingsCard(
          title: 'Профиль',
          children: [
            SettingsField(
              controller: _nameCtrl,
              maxLength: 64,
              label: 'Имя для синхронизации',
              prefixIcon: Icon(
                Icons.person_outline,
                size: 20,
                color: SettingsTokens.iconProfile,
              ),
            ),
            SettingsField(
              controller: _syncCtrl,
              maxLength: 200,
              label: 'Адрес сервера синхронизации',
              hint: 'оставьте пустым для оффлайн-режима',
              prefixIcon: Icon(
                Icons.cloud_outlined,
                size: 20,
                color: SettingsTokens.iconSync,
              ),
            ),
          ],
        ),
      );
    }

    if (_visible(['Лимит размера книги', 'МБ'])) {
      children.add(
        SettingsCard(
          title: 'Лимит размера книги',
          children: [
            Row(
              children: [
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label:
                        '${(_s.maxBookSizeBytes / (1024 * 1024)).toStringAsFixed(0)} МБ',
                    value: _s.maxBookSizeBytes / (1024 * 1024),
                    onChanged: (v) => setState(() {
                      _s.maxBookSizeBytes = v * 1024 * 1024;
                    }),
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    '${(_s.maxBookSizeBytes / (1024 * 1024)).toStringAsFixed(1)} МБ',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: SettingsTokens.rowTitleSize,
                      color: SettingsTokens.text(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_visible(['ИИ-разбор фрагмента', 'Провайдер', 'Модель', 'API-ключ'])) {
      children.add(
        SettingsCard(
          title: 'ИИ-разбор фрагмента',
          children: [
            DropdownButtonFormField<AiProvider>(
              initialValue: _s.ai.provider,
              isExpanded: true,
              decoration: settingsInputDecoration(
                context,
                label: 'Провайдер',
                prefixIcon: Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: SettingsTokens.iconAi,
                ),
              ),
              dropdownColor: SettingsTokens.card(context),
              borderRadius: BorderRadius.circular(SettingsTokens.radiusCard),
              items: AiProvider.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                  .toList(),
              onChanged: (v) => setState(() {
                if (v != null) {
                  _s.ai.provider = v;
                  _s.ai.baseUrl = v.baseUrl;
                  _s.ai.model = v.defaultModel;
                  _aiModelCtrl.text = v.defaultModel;
                  _aiUrlCtrl.text = v.baseUrl;
                  _ollamaModels = const [];
                  if (v == AiProvider.ollama) _reloadOllamaModels();
                }
              }),
            ),
            if (_s.ai.provider.needsKey)
              SettingsField(
                controller: _aiKeyCtrl,
                maxLength: 200,
                label: 'API-ключ',
                obscureText: true,
                prefixIcon: Icon(
                  Icons.vpn_key_outlined,
                  size: 20,
                  color: SettingsTokens.iconSecurity,
                ),
                onChanged: (v) => _s.ai.apiKey = v,
              )
            else if (_s.ai.provider == AiProvider.free)
              const _Note(
                'Бесплатный общедоступный ИИ без ключа (Pollinations). '
                'Работает через интернет — подходит и для телефона. '
                'Возможны лимиты на частоту запросов.',
              )
            else ...[
              if (_ollamaModels.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _ollamaModels.contains(_s.ai.model)
                      ? _s.ai.model
                      : _ollamaModels.first,
                  isExpanded: true,
                  decoration: settingsInputDecoration(
                    context,
                    label: 'Модель из Ollama',
                    helper: 'Установлено: ${_ollamaModels.join(', ')}',
                  ),
                  dropdownColor: SettingsTokens.card(context),
                  borderRadius: BorderRadius.circular(
                    SettingsTokens.radiusCard,
                  ),
                  items: _ollamaModels
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    if (v != null) {
                      _s.ai.model = v;
                      _aiModelCtrl.text = v;
                    }
                  }),
                ),
              SettingsField(
                controller: _aiUrlCtrl,
                maxLength: 300,
                label: 'Адрес Ollama (локально)',
                prefixIcon: Icon(
                  Icons.lan_outlined,
                  size: 20,
                  color: SettingsTokens.iconStorage,
                ),
                onChanged: (v) => _s.ai.baseUrl = v,
              ),
              _Note(
                _ollamaModels.isEmpty
                    ? 'Ollama не отвечает или не запущена. Установите Ollama '
                          'и запросите модель, например: ollama pull qwen2.5:3b. '
                          'Модель работает локально, без интернета и ключей.'
                    : 'Модель выбрана из установленных. Для других моделей '
                          'запустите: ollama pull <название>.',
              ),
            ],
            if (!_s.ai.provider.needsKey && _s.ai.provider != AiProvider.free)
              SettingsField(
                controller: _aiModelCtrl,
                maxLength: 120,
                label: 'Модель',
                prefixIcon: Icon(
                  Icons.memory,
                  size: 20,
                  color: SettingsTokens.iconMetadata,
                ),
                onChanged: (v) => _s.ai.model = v,
              ),
          ],
        ),
      );
    }

    if (_visible(['Поиск книг', 'OPDS', 'каталог', 'Добавить каталог'])) {
      children.add(
        SettingsCard(
          title: 'Поиск книг (OPDS-каталоги)',
          children: [
            for (final e in _s.catalogs.asMap().entries)
              SettingsRow(
                title: e.value.name,
                subtitle: e.value.url,
                icon: Icons.cloud_outlined,
                iconColor: SettingsTokens.iconMedia,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: SettingsTokens.iconSupport,
                  onPressed: () => setState(() {
                    _s.catalogs.removeAt(e.key);
                  }),
                ),
              ),
            SettingsRow(
              title: 'Добавить каталог',
              icon: Icons.add,
              iconColor: SettingsTokens.iconDownload,
              onTap: _addCatalog,
            ),
          ],
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
          child: Text(
            'Для интернет-поиска приложение уже включает Project Gutenberg '
            '(бесплатные книги) и редактируемый список OPDS. Скачанные книги '
            'читаются полностью оффлайн.',
            style: TextStyle(
              color: muted,
              fontSize: SettingsTokens.rowSubtitleSize,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(
          'QutZem Reader v$appVersion · автор: QutZem',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: SettingsTokens.background(context),
      body: SettingsView(
        title: 'Настройки читалки',
        onBack: () => Navigator.pop(context),
        search: SettingsSearch(
          hint: 'Настройки поиска',
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        trailing: null,
        actions: SettingsActionBarButton(
          label: 'Сохранить',
          icon: Icons.check,
          onPressed: _save,
        ),
        children: children,
      ),
    );
  }

  Future<void> _addCatalog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый OPDS-каталог'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsField(
              controller: nameCtrl,
              maxLength: 64,
              label: 'Название',
            ),
            const SizedBox(height: 12),
            SettingsField(
              controller: urlCtrl,
              maxLength: 400,
              label: 'URL (OPDS Atom или JSON)',
              hint: 'https://…',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final name = nameCtrl.text.trim();
      final url = urlCtrl.text.trim();
      if (name.isNotEmpty && url.isNotEmpty) {
        setState(() {
          _s.catalogs.add(OpdsCatalog(name: name, url: url));
        });
      }
    }
  }
}

/// Пояснение под полем внутри карточки.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: TextStyle(
          color: SettingsTokens.muted(context),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

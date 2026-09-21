import 'package:flutter/material.dart';

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
  late AppSettings _s;
  List<String> _ollamaModels = const [];

  @override
  void initState() {
    super.initState();
    _s = AppSettings.fromJson(widget.settings.toJson());
    _nameCtrl =
        TextEditingController(text: _s.displayName);
    _syncCtrl = TextEditingController(text: _s.syncServer);
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
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _syncCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Профиль'),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Имя для синхронизации',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _syncCtrl,
            decoration: const InputDecoration(
              labelText: 'Адрес сервера синхронизации (интернет)',
              hintText: 'оставьте пустым для оффлайн-режима',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Лимит размера книги'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '${(_s.maxBookSizeBytes / (1024 * 1024)).toStringAsFixed(0)} МБ',
                  value: _s.maxBookSizeBytes / (1024 * 1024),
                  onChanged: (v) => setState(() {
                    _s.maxBookSizeBytes = v * 1024 * 1024;
                  }),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  '${(_s.maxBookSizeBytes / (1024 * 1024)).toStringAsFixed(1)} МБ',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle('ИИ-разбор фрагмента'),
          DropdownButtonFormField<AiProvider>(
            initialValue: _s.ai.provider,
            decoration: const InputDecoration(
              labelText: 'Провайдер',
              border: OutlineInputBorder(),
            ),
            items: AiProvider.values
                .map((p) => DropdownMenuItem(
                    value: p, child: Text(p.label)))
                .toList(),
            onChanged: (v) => setState(() {
              if (v != null) {
                _s.ai.provider = v;
                _s.ai.baseUrl = v.baseUrl;
                _s.ai.model = v.defaultModel;
                _ollamaModels = const [];
                if (v == AiProvider.ollama) _reloadOllamaModels();
              }
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Модель',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: _s.ai.model),
            onChanged: (v) => _s.ai.model = v,
          ),
          const SizedBox(height: 8),
          if (_s.ai.provider.needsKey) ...[
            TextField(
              controller:
                  TextEditingController(text: _s.ai.apiKey),
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API-ключ',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _s.ai.apiKey = v,
            ),
          ] else if (_s.ai.provider == AiProvider.free) ...[
            const SizedBox(height: 4),
            const Text(
              'Бесплатный общедоступный ИИ без ключа (Pollinations). '
              'Работает через интернет — подходит и для телефона. '
              'Возможны лимиты на частоту запросов.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ] else ...[
            if (_ollamaModels.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _ollamaModels.contains(_s.ai.model)
                    ? _s.ai.model
                    : _ollamaModels.first,
                decoration: InputDecoration(
                  labelText: 'Модель из Ollama',
                  helperText:
                      'Установлено: ${_ollamaModels.join(', ')}',
                  border: const OutlineInputBorder(),
                ),
                items: _ollamaModels
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() {
                  if (v != null) _s.ai.model = v;
                }),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: TextEditingController(text: _s.ai.baseUrl),
              decoration: const InputDecoration(
                labelText: 'Адрес Ollama (локально)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _s.ai.baseUrl = v,
            ),
            const SizedBox(height: 4),
            Text(
              _ollamaModels.isEmpty
                  ? 'Ollama не отвечает или не запущена. Установите Ollama '
                      'и запросите модель, например: ollama pull qwen2.5:3b. '
                      'Модель работает локально, без интернета и ключей.'
                  : 'Модель выбрана из установленных. Для других моделей '
                      'запустите: ollama pull <название>.',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          _sectionTitle('Поиск книг (OPDS-каталоги)'),
          ..._s.catalogs.asMap().entries.map((e) {
            return Card(
              child: ListTile(
                dense: true,
                title: Text(e.value.name),
                subtitle: Text(e.value.url,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() {
                    _s.catalogs.removeAt(e.key);
                  }),
                ),
              ),
            );
          }),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Добавить каталог'),
            onTap: _addCatalog,
          ),
          const SizedBox(height: 8),
          Text(
            'Для интернет-поиска приложение уже включает Project '
            'Gutenberg (бесплатные книги) и редактируемый список OPDS. '
            'Скачанные книги читаются полностью оффлайн.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const Divider(height: 32),
          Text(
            'QutZem Reader v$appVersion · автор: QutZem',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL (OPDS Atom или JSON)',
                hintText: 'https://…',
              ),
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
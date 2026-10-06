import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

import '../ai.dart';
import '../screens/search_screen.dart';
import '../search.dart';
import '../settings.dart';

/// Открывает экран «Распознать текст».
///
/// [ctx] — текущая книга: подсказка для распознавания и запасной вариант,
/// если ИИ не сможет определить название. [onOpenSettings] — переход в
/// настройки ИИ, когда ключа нет или провайдер не умеет картинки.
Future<void> showScanRecognize(
  BuildContext context, {
  required AiSettings aiSettings,
  AnalysisContext? ctx,
  Future<void> Function()? onOpenSettings,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ScanRecognizeScreen(
        aiSettings: aiSettings,
        ctx: ctx,
        onOpenSettings: onOpenSettings,
      ),
    ),
  );
}

/// Экран распознавания текста со снимка или файла.
///
/// Схема работы: выбрать источник → отдать картинку зрению модели →
/// показать распознанный текст в обычном поле, чтобы читатель мог
/// поправить ошибки → выбрать действие (найти книгу, описать отрывок,
/// краткий пересказ).
class ScanRecognizeScreen extends StatefulWidget {
  final AiSettings aiSettings;
  final AnalysisContext? ctx;
  final Future<void> Function()? onOpenSettings;

  const ScanRecognizeScreen({
    super.key,
    required this.aiSettings,
    this.ctx,
    this.onOpenSettings,
  });

  @override
  State<ScanRecognizeScreen> createState() => _ScanRecognizeScreenState();
}

class _ScanRecognizeScreenState extends State<ScanRecognizeScreen> {
  final _textCtrl = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _source;
  String _sourceName = '';
  bool _busy = false;
  String? _error;
  bool _gotText = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = '$e';
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Камера есть не везде: на Windows её нет, и image_picker там её не ищет.
  bool get _cameraAvailable => !Platform.isWindows;

  Future<void> _chooseSource() async {
    final options = <_Source>[
      _Source.file, // выбор файла: картинка или PDF
      _Source.gallery, // галерея телефона
      if (_cameraAvailable) _Source.camera, // снимок камерой
    ];
    final choice = await showModalBottomSheet<_Source>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in options)
              ListTile(
                leading: Icon(o.icon),
                title: Text(o.title),
                subtitle: o.subtitle == null ? null : Text(o.subtitle!),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _Source.file:
        await _pickFile();
      case _Source.gallery:
        await _pickFromPicker(ImageSource.gallery);
      case _Source.camera:
        await _pickFromPicker(ImageSource.camera);
    }
  }

  Future<void> _pickFile() async {
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'pdf'],
      );
    } catch (e) {
      _fail(e);
      return;
    }
    final path = file?.path;
    if (path == null || !mounted) return;
    if (p.extension(path).toLowerCase() == 'pdf') {
      await _askPdfPage(path, file!.name);
    } else {
      await _useBytes(
        Uint8List.fromList(File(path).readAsBytesSync()),
        file!.name,
      );
    }
  }

  /// У PDF спрашиваем страницу: в книге нужна конкретная, а не первая.
  Future<void> _askPdfPage(String path, String name) async {
    final controller = TextEditingController(text: '1');
    final page = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Страница в «$name»'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Номер страницы'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim()) ?? 1),
            child: const Text('Распознать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (page == null || page < 1 || !mounted) return;
    await _usePdfPage(path, name, page);
  }

  /// Отдаёт страницу PDF как картинку: в сканах текстового слоя нет,
  /// поэтому распознавать приходится именно изображение.
  Future<void> _usePdfPage(String path, String name, int page) async {
    setState(() {
      _busy = true;
      _error = null;
      _sourceName = '$name, стр. $page';
    });
    try {
      final doc = await PdfDocument.openFile(path);
      final count = doc.pagesCount;
      if (page > count) {
        await doc.close();
        throw Exception(
          'В файле всего $count ${_plural(count, 'страница', 'страницы', 'страниц')}',
        );
      }
      final pdfPage = await doc.getPage(page);
      // Страницу рендерим с запасом по высоте: пропорции нам неизвестны,
      // а текст должен остаться читаемым после уменьшения до 1600px.
      final image = await pdfPage.render(
        width: 1700,
        height: 2300,
        format: PdfPageImageFormat.png,
      );
      await pdfPage.close();
      await doc.close();
      if (image == null) throw Exception('Не удалось отрисовать страницу');
      await _recognize(image.bytes);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _pickFromPicker(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (file == null || !mounted) return;
      await _useBytes(await file.readAsBytes(), file.name);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _useBytes(Uint8List bytes, String name) async {
    if (!mounted) return;
    setState(() {
      _source = bytes;
      _sourceName = name;
      _error = null;
      _busy = true;
    });
    await _recognize(bytes);
  }

  Future<void> _recognize(Uint8List bytes) async {
    try {
      final prepared = prepareImageForAi(bytes);
      final text = await AiService(widget.aiSettings).recognizeTextFromImage(
        imageBytes: prepared,
        mimeType: 'image/jpeg',
        bookHint: widget.ctx?.bookTitle,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _gotText = text.trim().isNotEmpty;
        _textCtrl.text = text.trim();
      });
      if (!_gotText) {
        _snack('На изображении не нашлось текста. Попробуйте чётче или ближе.');
      }
    } catch (e) {
      _fail(e);
    }
  }

  /// ИИ определяет книгу, читатель подтверждает или правит название — и
  /// поиск уходит в уже готовый экран каталога со скачиванием.
  Future<void> _findBookOnline() async {
    final fragment = _textCtrl.text.trim();
    if (fragment.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final identified = await AiService(widget.aiSettings)
          .identifyBook(fragment, ctx: widget.ctx);
      if (!mounted) return;
      setState(() => _busy = false);

      final titleCtrl = TextEditingController(
        text: identified.title.isNotEmpty
            ? identified.title
            : widget.ctx?.bookTitle ?? '',
      );
      final authorCtrl = TextEditingController(text: identified.author);
      final query = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Найти книгу в интернете'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: authorCtrl,
                decoration: const InputDecoration(labelText: 'Автор'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Искать'),
              onPressed: () {
                final t = titleCtrl.text.trim();
                final a = authorCtrl.text.trim();
                Navigator.pop(ctx, [t, a].where((s) => s.isNotEmpty).join(' '));
              },
            ),
          ],
        ),
      );
      titleCtrl.dispose();
      authorCtrl.dispose();
      if (query == null || query.trim().isEmpty || !mounted) return;

      final oo = SettingsStore.instance.oo;
      final catalogs = oo.catalogs.isEmpty
          ? SearchService.defaultCatalogs
          : oo.catalogs;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SearchScreen(catalogs: catalogs, initialQuery: query.trim()),
        ),
      );
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _askAi(AiPromptKind kind) async {
    final fragment = _textCtrl.text.trim();
    if (fragment.isEmpty) return;
    await showAiAnalysisDialog(
      context,
      widget.aiSettings,
      fragment,
      ctx: widget.ctx,
      kind: kind,
      onOpenSettings: widget.onOpenSettings,
    );
  }

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: _textCtrl.text));
    _snack('Текст скопирован');
  }

  static String _plural(int n, String one, String few, String many) {
    if (n % 10 == 1 && n % 100 != 11) return one;
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return few;
    }
    return many;
  }

  @override
  Widget build(BuildContext context) {
    final vision = widget.aiSettings.provider.supportsVision;
    return Scaffold(
      appBar: AppBar(title: const Text('Распознать текст')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_sourceName.isNotEmpty)
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(
                  _sourceName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Нажмите, чтобы взять другой источник'),
                onTap: _busy ? null : _chooseSource,
              ),
            ),
          if (!vision)
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Провайдер «${widget.aiSettings.provider.label}» не умеет '
                        'читать картинки. Выберите другого в настройках ИИ.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (widget.onOpenSettings != null)
                      TextButton(
                        onPressed: widget.onOpenSettings,
                        child: const Text('Настроить'),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Читаю текст с изображения…'),
                ],
              ),
            )
          else ...[
            if (_error != null)
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error!)),
                    ],
                  ),
                ),
              ),
            TextField(
              controller: _textCtrl,
              maxLines: 12,
              minLines: 6,
              decoration: InputDecoration(
                labelText: _gotText ? 'Распознанный текст' : 'Текст',
                hintText:
                    'Здесь появится текст со снимка. '
                    'Его можно поправить перед поиском.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _chooseSource,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Скриншот или файл'),
                ),
                const SizedBox(width: 8),
                if (_source != null)
                  IconButton(
                    tooltip: 'Распознать заново',
                    onPressed: () async {
                      final bytes = _source;
                      if (bytes == null) return;
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      await _recognize(bytes);
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                if (_gotText)
                  IconButton(
                    onPressed: _copyText,
                    icon: const Icon(Icons.copy),
                    tooltip: 'Скопировать',
                  ),
              ],
            ),
            const Divider(height: 32),
            Text(
              'Что сделать с текстом',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _ActionButton(
              icon: Icons.travel_explore,
              title: 'Найти книгу в интернете',
              subtitle:
                  'ИИ определит название и автора, дальше — поиск и скачивание',
              onPressed: _findBookOnline,
            ),
            _ActionButton(
              icon: Icons.auto_stories_outlined,
              title: 'Описать отрывок',
              subtitle: 'Где происходит действие и кто в нём участвует',
              onPressed: () => _askAi(AiPromptKind.passageDescription),
            ),
            _ActionButton(
              icon: Icons.short_text,
              title: 'Краткий пересказ',
              subtitle: 'Три-четыре предложения о сути',
              onPressed: () => _askAi(AiPromptKind.briefSummary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onPressed,
      ),
    );
  }
}

enum _Source { file, gallery, camera }

extension on _Source {
  IconData get icon => switch (this) {
    _Source.file => Icons.insert_drive_file_outlined,
    _Source.gallery => Icons.photo_library_outlined,
    _Source.camera => Icons.photo_camera_outlined,
  };

  String get title => switch (this) {
    _Source.file => 'Выбрать файл',
    _Source.gallery => 'Галерея',
    _Source.camera => 'Снять камерой',
  };

  String? get subtitle => switch (this) {
    _Source.file => 'Картинка или PDF со сканом',
    _Source.gallery => 'Фото из галереи телефона',
    _Source.camera => null,
  };
}

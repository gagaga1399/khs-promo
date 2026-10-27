import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/note_template.dart';
import '../services/tracker_service.dart';
import '../state/app_state.dart';
import 'note_template_editor_screen.dart';
import 'tracker_accent.dart';
import 'vault_note_viewer_screen.dart';
import 'widgets/note_properties_editor.dart';

/// Проводник заметок из хранилища Obsidian: дерево папок и markdown-файлов.
/// Используется вкладкой «Заметки» приложения трекеров.
class VaultNotesPanel extends StatefulWidget {
  const VaultNotesPanel({super.key});

  @override
  State<VaultNotesPanel> createState() => _VaultNotesPanelState();
}

/// Данные перетаскивания в дереве заметок: относительный путь и признак того,
/// что перетаскивается папка (а не markdown-файл).
class _NoteDragData {
  const _NoteDragData(this.path, {required this.isFolder});

  final String path;
  final bool isFolder;
}

class _VaultNotesPanelState extends State<VaultNotesPanel> {
  final Set<String> _expanded = <String>{};

  Future<List<String>>? _files;

  /// Хранилище, для которого выполнен текущий скан (чтобы пересобрать дерево
  /// при смене пути в настройках).
  String _scannedVault = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _rescan());
  }

  void _rescan() {
    if (!mounted) return;
    final obsidian = context.read<AppState>().obsidian;
    _scannedVault = obsidian.vaultPath.trim();
    _expanded.clear();
    setState(() {
      _files = obsidian.listMarkdownFiles();
    });
  }

  /// Создание заметки из шаблона: выбор шаблона, названия и свойств, запись
  /// файла в корень хранилища и открытие в просмотрщике.
  Future<void> _createNote() async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final vault = state.obsidian.vaultPath.trim();
    if (vault.isEmpty) return;
    final result = await showModalBottomSheet<({String title, String content})>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _CreateNoteSheet(
        state: state,
        accent: trackerBaseAccent(context),
      ),
    );
    if (result == null || !mounted) return;
    final title = result.title.trim();
    if (title.isEmpty) return;
    try {
      final safe = _safeFileName(title);
      var file = File(p.join(vault, '$safe.md'));
      var suffix = 2;
      while (await file.exists()) {
        file = File(p.join(vault, '$safe ($suffix).md'));
        suffix++;
      }
      await file.writeAsString(result.content, encoding: utf8);
      if (!mounted) return;
      _rescan();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.t('noteCreated'))),
      );
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => VaultNoteViewerScreen(path: file.path, title: title),
        ),
      );
      if (mounted) _rescan();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.t('noteCreateFailed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final vault = state.obsidian.vaultPath.trim();

    if (vault != _scannedVault) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rescan();
      });
    }

    if (vault.isEmpty) {
      return _Empty(
        icon: Icons.folder_off_outlined,
        title: strings.t('vaultNotesNoVault'),
        body: strings.t('vaultNotesNoVaultHelp'),
      );
    }

    return FutureBuilder<List<String>>(
      future: _files,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final rel = snapshot.data ?? const <String>[];
        if (rel.isEmpty) {
          return _Empty(
            icon: Icons.search_off_outlined,
            title: strings.t('vaultNotesEmpty'),
            body: vault,
            createLabel: strings.t('noteCreate'),
            onCreate: _createNote,
          );
        }
        return Column(
          children: [
            _header(context, strings, vault),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                children: _rows(context, rel),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, AppStrings strings, String vault) {
    final scheme = Theme.of(context).colorScheme;
    final name = p.basename(vault);
    return DragTarget<_NoteDragData>(
      onWillAcceptWithDetails: (details) => _canDropInto(details.data, ''),
      onAcceptWithDetails: (details) => _moveToFolder(details.data, ''),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: hovering
              ? trackerBaseAccent(context).withValues(alpha: 0.12)
              : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? vault : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.t('noteCreate'),
                icon: const Icon(Icons.note_add_outlined, size: 20),
                onPressed: _createNote,
              ),
              IconButton(
                tooltip: strings.t('trackerRefresh'),
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _rescan,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _rows(BuildContext context, List<String> rel) {
    final folders = <String, Set<String>>{};
    final files = <String, List<String>>{};
    for (final path in rel) {
      final segments = path.split('/');
      var prefix = '';
      for (var i = 0; i < segments.length - 1; i++) {
        final child = prefix.isEmpty ? segments[i] : '$prefix/${segments[i]}';
        folders.putIfAbsent(prefix, () => <String>{}).add(child);
        prefix = child;
      }
      files.putIfAbsent(prefix, () => <String>[]).add(segments.last);
    }

    final out = <Widget>[];
    void walk(String path, int depth) {
      final kids = (folders[path]?.toList() ?? <String>[])
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      for (final folder in kids) {
        final name = folder.substring(folder.lastIndexOf('/') + 1);
        out.add(_folderRow(context, folder, name, depth));
        if (_expanded.contains(folder)) walk(folder, depth + 1);
      }
      final names = (files[path] ?? <String>[])
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      for (final name in names) {
        final full = path.isEmpty ? name : '$path/$name';
        out.add(_fileRow(context, full, name, depth));
      }
    }

    walk('', 0);
    return out;
  }

  Widget _folderRow(
    BuildContext context,
    String folder,
    String name,
    int depth,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final open = _expanded.contains(folder);
    return DragTarget<_NoteDragData>(
      onWillAcceptWithDetails: (details) => _canDropInto(details.data, folder),
      onAcceptWithDetails: (details) => _moveToFolder(details.data, folder),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        final row = InkWell(
          onTap: () => setState(() {
            if (!_expanded.add(folder)) _expanded.remove(folder);
          }),
          child: Container(
            decoration: hovering
                ? BoxDecoration(
                    color: trackerBaseAccent(context).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            padding: EdgeInsets.fromLTRB(8 + depth * 16, 9, 8, 9),
            child: Row(
              children: [
                Icon(
                  open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Icon(
                  hovering ? Icons.folder_open : Icons.folder_outlined,
                  size: 18,
                  color: trackerBaseAccent(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
        return Draggable<_NoteDragData>(
          data: _NoteDragData(folder, isFolder: true),
          feedback: _dragFeedback(context, name, isFolder: true),
          childWhenDragging: Opacity(opacity: 0.35, child: row),
          child: row,
        );
      },
    );
  }

  Widget _fileRow(
    BuildContext context,
    String relative,
    String name,
    int depth,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final strings = context.read<AppState>().strings;
    final title = name.toLowerCase().endsWith('.md')
        ? name.substring(0, name.length - 3)
        : name;
    final row = InkWell(
      onTap: () => _openNote(relative, title),
      onLongPress: () => _showNoteActions(relative, title),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8 + depth * 16 + 20, 4, 4, 4),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 17,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: strings.t('vaultNoteActions'),
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onSelected: (value) {
                if (value == 'move') {
                  _moveNote(context, relative, title);
                } else if (value == 'delete') {
                  _deleteNote(context, relative, title);
                }
              },
              itemBuilder: (menuContext) => [
                PopupMenuItem(
                  value: 'move',
                  child: Text(strings.t('vaultNoteMove')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(strings.t('vaultNoteDelete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return Draggable<_NoteDragData>(
      data: _NoteDragData(relative, isFolder: false),
      feedback: _dragFeedback(context, title, isFolder: false),
      childWhenDragging: Opacity(opacity: 0.35, child: row),
      child: row,
    );
  }

  Widget _dragFeedback(
    BuildContext context,
    String title, {
    required bool isFolder,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFolder ? Icons.folder_outlined : Icons.description_outlined,
              size: 16,
              color: isFolder
                  ? trackerBaseAccent(context)
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _showNoteActions(String relative, String title) async {
    final strings = context.read<AppState>().strings;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(strings.t('vaultNoteMove')),
              onTap: () => Navigator.pop(sheetContext, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(strings.t('vaultNoteDelete')),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'move') {
      await _moveNote(context, relative, title);
    } else if (action == 'delete') {
      await _deleteNote(context, relative, title);
    }
  }

  Future<void> _openNote(String relative, String title) async {
    final vault = context.read<AppState>().obsidian.vaultPath.trim();
    final absolute = p.joinAll([vault, ...relative.split('/')]);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VaultNoteViewerScreen(path: absolute, title: title),
      ),
    );
    if (mounted) _rescan();
  }

  Future<void> _deleteNote(
    BuildContext context,
    String relative,
    String title,
  ) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final vault = state.obsidian.vaultPath.trim();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(
          strings.t('vaultNoteDeleteConfirm').replaceFirst('{name}', title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await File(p.joinAll([vault, ...relative.split('/')])).delete();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('vaultNoteDeleteFailed'))),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(strings.t('vaultNoteDeleted'))),
    );
    if (mounted) _rescan();
  }

  Future<void> _moveNote(
    BuildContext context,
    String relative,
    String title,
  ) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    var value = relative;
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.t('vaultNoteMoveTitle')),
        content: TextFormField(
          initialValue: relative,
          autofocus: true,
          decoration: InputDecoration(hintText: strings.t('vaultNoteMoveHint')),
          onChanged: (text) => value = text,
          onFieldSubmitted: (text) => Navigator.pop(dialogContext, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: Text(strings.t('ok')),
          ),
        ],
      ),
    );
    if (input == null) return;

    var target = input.trim().replaceAll('\\', '/');
    if (target.isEmpty) return;
    if (!target.toLowerCase().endsWith('.md')) target = '$target.md';
    final segs = target
        .split('/')
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
    if (segs.isEmpty) return;
    final normalized = segs.join('/');
    if (normalized == relative) return;
    await _performMove(relative, normalized);
  }

  /// Можно ли перетащить элемент [data] в папку `folder` (папка не должна
  /// совпадать с текущей папкой, а папку нельзя вложить в саму себя).
  bool _canDropInto(_NoteDragData data, String folder) {
    final relative = data.path;
    final index = relative.lastIndexOf('/');
    final current = index < 0 ? '' : relative.substring(0, index);
    if (current == folder) return false;
    if (data.isFolder) {
      if (folder == relative) return false;
      if (folder.startsWith('$relative/')) return false;
    }
    return true;
  }

  /// Перетаскивание: перенос заметки/папки в папку `folder` (пусто — корень).
  Future<void> _moveToFolder(_NoteDragData data, String folder) async {
    final name = data.path.substring(data.path.lastIndexOf('/') + 1);
    final target = folder.isEmpty ? name : '$folder/$name';
    await _performMove(data.path, target);
  }

  /// Физический перенос файла или папки на новый относительный путь с
  /// уведомлением и пересборкой дерева.
  Future<void> _performMove(String relative, String newRelative) async {
    if (newRelative == relative) return;
    final state = context.read<AppState>();
    final strings = state.strings;
    final vault = state.obsidian.vaultPath.trim();
    final messenger = ScaffoldMessenger.of(context);
    final fromPath = p.joinAll([vault, ...relative.split('/')]);
    final toPath = p.joinAll([vault, ...newRelative.split('/')]);
    final fromDir = Directory(fromPath);
    final isFolder = await fromDir.exists();
    if (await File(toPath).exists() || await Directory(toPath).exists()) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('vaultNoteMoveExists'))),
      );
      return;
    }
    try {
      await Directory(p.dirname(toPath)).create(recursive: true);
      if (isFolder) {
        await fromDir.rename(toPath);
      } else {
        await File(fromPath).rename(toPath);
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('vaultNoteMoveFailed'))),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(strings.t('vaultNoteMoved'))),
    );
    if (mounted) _rescan();
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    this.createLabel,
    this.onCreate,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? createLabel;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: Text(createLabel ?? ''),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Безопасное имя файла заметки: недопустимые символы заменяются пробелом,
/// отбрасываются завершающие пробелы/точки и пустой результат.
String _safeFileName(String name) {
  var s = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  while (s.endsWith('.') || s.endsWith(' ')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) s = 'Note';
  return s;
}

/// Встроенный шаблон заметки: заголовок/описание в локализации и заготовка
/// тела, куда подставляются название заметки и текущая дата.
class _NoteTemplate {
  const _NoteTemplate({
    required this.titleKey,
    required this.descKey,
    required this.icon,
    required this.body,
  });

  final String titleKey;
  final String descKey;
  final IconData icon;
  final String Function(String title, DateTime now) body;
}

String _formatNoteDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day.$month.${d.year}';
}

final List<_NoteTemplate> _builtinNoteTemplates = <_NoteTemplate>[
  _NoteTemplate(
    titleKey: 'noteTemplateEmpty',
    descKey: 'noteTemplateEmptyDesc',
    icon: Icons.note_outlined,
    body: (title, _) => '# $title\n',
  ),
  _NoteTemplate(
    titleKey: 'noteTemplateDaily',
    descKey: 'noteTemplateDailyDesc',
    icon: Icons.today_outlined,
    body: (title, now) => '# $title\n\n'
        '**Дата:** ${_formatNoteDate(now)}\n\n'
        '## Сделано\n'
        '- \n\n'
        '## Планы\n'
        '- \n\n'
        '## Итоги\n'
        '- \n',
  ),
  _NoteTemplate(
    titleKey: 'noteTemplateTodos',
    descKey: 'noteTemplateTodosDesc',
    icon: Icons.checklist_outlined,
    body: (title, _) => '# $title\n\n- [ ] \n- [ ] \n- [ ] \n',
  ),
  _NoteTemplate(
    titleKey: 'noteTemplateIdea',
    descKey: 'noteTemplateIdeaDesc',
    icon: Icons.lightbulb_outlined,
    body: (title, _) => '# $title\n\n'
        '## Мысль\n\n\n'
        '## Почему это важно\n\n\n'
        '## Шаги\n'
        '- \n',
  ),
  _NoteTemplate(
    titleKey: 'noteTemplateMeeting',
    descKey: 'noteTemplateMeetingDesc',
    icon: Icons.groups_outlined,
    body: (title, now) => '# $title\n\n'
        '**Дата:** ${_formatNoteDate(now)}\n\n'
        '## Повестка\n'
        '- \n\n'
        '## Решения\n'
        '- \n',
  ),
];

/// Обёртка над встроенным или пользовательским шаблоном для списка выбора.
class _TemplateOption {
  const _TemplateOption.builtin(this._builtin) : _custom = null;

  const _TemplateOption.custom(this._custom) : _builtin = null;

  final _NoteTemplate? _builtin;
  final NoteTemplate? _custom;

  bool get isCustom => _custom != null;

  NoteTemplate? get custom => _custom;

  String name(AppStrings strings) =>
      _builtin != null ? strings.t(_builtin.titleKey) : _custom!.name;

  String? description(AppStrings strings) =>
      _builtin != null ? strings.t(_builtin.descKey) : null;

  IconData get icon => _builtin?.icon ?? Icons.description_outlined;

  String bodyFor(String title, DateTime now) => _builtin != null
      ? _builtin.body(title, now)
      : _custom!.bodyFor(title, now);

  List<NotePropertySpec> get properties =>
      _custom?.properties ?? const <NotePropertySpec>[];

  bool matches(_TemplateOption other) {
    if (_builtin != null) return identical(_builtin, other._builtin);
    return _custom != null &&
        other._custom != null &&
        _custom.id == other._custom.id;
  }
}

/// Нижняя панель создания заметки: название, шаблон (встроенный или свой),
/// свойства (frontmatter). Возвращает `(title, content)` через `Navigator.pop`.
class _CreateNoteSheet extends StatefulWidget {
  const _CreateNoteSheet({required this.state, required this.accent});

  final AppState state;
  final Color accent;

  @override
  State<_CreateNoteSheet> createState() => _CreateNoteSheetState();
}

class _CreateNoteSheetState extends State<_CreateNoteSheet> {
  final TextEditingController _name = TextEditingController();
  final List<NotePropertyDraft> _properties = [];
  int _nextId = 0;
  late _TemplateOption _selected;

  @override
  void initState() {
    super.initState();
    _selected = _TemplateOption.builtin(_builtinNoteTemplates.first);
    _name.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    super.dispose();
  }

  List<_TemplateOption> _options() => [
    for (final template in _builtinNoteTemplates)
      _TemplateOption.builtin(template),
    for (final template in widget.state.noteTemplates)
      _TemplateOption.custom(template),
  ];

  void _selectOption(_TemplateOption option) {
    setState(() {
      _selected = option;
      _properties
        ..clear()
        ..addAll(
          option.properties.map(
            (spec) => NotePropertyDraft(
              id: _nextId++,
              key: spec.key,
              value: spec.value,
            ),
          ),
        );
    });
  }

  void _addProperty() {
    setState(() {
      _properties.add(NotePropertyDraft(id: _nextId++, key: '', value: ''));
    });
  }

  void _removeProperty(NotePropertyDraft draft) {
    setState(() => _properties.remove(draft));
  }

  Future<void> _editTemplate(
    BuildContext context, {
    NoteTemplate? existing,
  }) async {
    final state = widget.state;
    final result = await Navigator.of(context).push<NoteTemplateEditResult>(
      MaterialPageRoute(
        builder: (_) => NoteTemplateEditorScreen(existing: existing),
      ),
    );
    if (!mounted || result == null) return;
    if (result.deleted) {
      if (existing != null) await state.deleteNoteTemplate(existing.id);
      if (mounted) setState(() {});
      return;
    }
    final template = result.template!;
    await state.saveNoteTemplate(template);
    if (!mounted) return;
    _selectOption(_TemplateOption.custom(template));
  }

  void _submit(BuildContext context) {
    final title = _name.text.trim();
    if (title.isEmpty) return;
    final now = DateTime.now();
    final body = _selected.bodyFor(title, now);
    final map = <String, Object?>{};
    for (final draft in _properties) {
      final key = draft.key.trim();
      if (key.isEmpty) continue;
      map[key] = draft.value;
    }
    final frontmatter = TrackerService.buildFrontmatter(map);
    final content = frontmatter.isEmpty ? body : '$frontmatter$body';
    Navigator.of(context).pop((title: title, content: content));
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.state.strings;
    final scheme = Theme.of(context).colorScheme;
    final canSubmit = _name.text.trim().isNotEmpty;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Text(
                    strings.t('noteCreate'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => canSubmit ? _submit(context) : null,
                    decoration: InputDecoration(
                      labelText: strings.t('noteTitle'),
                      hintText: strings.t('noteNameHint'),
                      prefixIcon: const Icon(Icons.title, size: 20),
                    ),
                  ),
                ),
                _sectionLabel(context, strings.t('noteTemplate')),
                for (final option in _options())
                  _templateTile(context, option),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _editTemplate(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(strings.t('noteTemplateCustom')),
                  ),
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                NotePropertiesEditor(
                  strings: strings,
                  properties: _properties,
                  onChanged: () {},
                  onAdd: _addProperty,
                  onRemove: _removeProperty,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: FilledButton(
                    onPressed: canSubmit ? () => _submit(context) : null,
                    child: Text(strings.t('noteCreateButton')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _templateTile(BuildContext context, _TemplateOption option) {
    final strings = widget.state.strings;
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent;
    final selected = option.matches(_selected);
    final showTrailing = option.isCustom || selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? accent : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Icon(
          option.icon,
          color: selected ? accent : scheme.onSurfaceVariant,
        ),
        title: Text(
          option.name(strings),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: option.description(strings) == null
            ? null
            : Text(option.description(strings)!),
        trailing: showTrailing
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (option.isCustom)
                    IconButton(
                      tooltip: strings.t('noteTemplateEdit'),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          _editTemplate(context, existing: option.custom),
                    ),
                  if (selected)
                    Icon(Icons.check_circle, color: accent, size: 20),
                ],
              )
            : null,
        onTap: () => _selectOption(option),
      ),
    );
  }
}

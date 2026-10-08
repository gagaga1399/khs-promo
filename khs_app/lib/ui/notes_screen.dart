import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/note.dart';
import '../state/app_state.dart';
import 'notes_editor_screen.dart';
import 'notes_tasks_screen.dart';
import 'notes_trash_screen.dart';

/// Панель заметок в виде файлового менеджера (как в Obsidian):
/// папки уровнем ниже, внутри — заметки; хлебные крошки, создание
/// папок, перемещение заметок и подстраница «Задачи» из корня.
class NotesPanel extends StatefulWidget {
  /// [showAddButton] — показывать ли крупную кнопку «Создать заметку» сверху.
  /// Кнопка одна и на телефоне, и на десктопе: отдельной плавающей нет.
  const NotesPanel({super.key, this.showAddButton = true});

  final bool showAddButton;

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  /// Текущая папка; `''` — корень.
  String _path = '';

  void _enter(String path) => setState(() => _path = path);

  void _goUp() => setState(() => _path = AppState.folderParent(_path));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final folders = state.childFolders(_path);
    final notes = state.notesInFolder(_path);
    final title = _path.isEmpty
        ? strings.t('notes')
        : AppState.folderName(_path);
    final isEmpty = folders.isEmpty && notes.isEmpty;
    final activeTasks = state.tasks.where((t) => !t.completed).length;

    final items = <Widget>[
      if (_path.isEmpty)
        _tasksEntryCard(
          context,
          strings,
          activeTasks,
          onOpen: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotesTasksScreen()),
          ),
        ),
      if (isEmpty)
        SizedBox(height: 220, child: _EmptyNotes(message: strings.t('noNotes')))
      else ...[
        for (final folder in folders) _folderCard(context, strings, folder),
        for (final note in notes) _noteCard(context, strings, note),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              if (_path.isNotEmpty)
                IconButton(
                  tooltip: strings.t('notes'),
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: _goUp,
                ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.t('trash'),
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotesTrashScreen()),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: strings.t('create'),
                icon: const Icon(Icons.add, size: 22),
                onSelected: (action) {
                  if (action == 'note') {
                    _openEditor();
                  } else {
                    _createFolder();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'note',
                    child: Text(strings.t('makeNewNote')),
                  ),
                  PopupMenuItem(
                    value: 'folder',
                    child: Text(strings.t('newFolder')),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_path.isNotEmpty) _breadcrumbs(context, strings),
        if (widget.showAddButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _openEditor,
                icon: const Icon(Icons.add),
                label: Text(strings.t('makeNewNote')),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              widget.showAddButton ? 16 : 104,
            ),
            children: _withGaps(items),
          ),
        ),
      ],
    );
  }

  List<Widget> _withGaps(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 12));
      out.add(items[i]);
    }
    return out;
  }

  void _openEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotesEditorScreen(folder: _path)),
    );
  }

  // -------------------------------------------------------------------------
  // Хлебные крошки: Заметки / Работа / Идеи
  // -------------------------------------------------------------------------

  Widget _breadcrumbs(BuildContext context, AppStrings strings) {
    final segments = <Widget>[
      _crumbButton(
        strings.t('notes'),
        bold: _path.isEmpty,
        onTap: () => setState(() => _path = ''),
      ),
    ];
    var cumulative = '';
    final parts = _path.split('/');
    for (var i = 0; i < parts.length; i++) {
      cumulative = i == 0 ? parts[i] : '$cumulative/${parts[i]}';
      final path = cumulative;
      segments.add(_crumbIcon());
      segments.add(
        _crumbButton(
          parts[i],
          bold: i == parts.length - 1,
          onTap: () => _enter(path),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: segments),
      ),
    );
  }

  Widget _crumbIcon() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Icon(
      Icons.chevron_right,
      size: 16,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _crumbButton(
    String label, {
    required bool bold,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: bold
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Карточки
  // -------------------------------------------------------------------------

  Widget _tasksEntryCard(
    BuildContext context,
    AppStrings strings,
    int activeTasks, {
    required VoidCallback onOpen,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.checklist_outlined, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.t('tasks'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (activeTasks > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$activeTasks',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _folderCard(BuildContext context, AppStrings strings, String path) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _enter(path),
        onLongPress: () => _folderActions(path),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  AppState.folderName(path),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteCard(BuildContext context, AppStrings strings, Note note) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('d MMM, HH:mm', strings.locale);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NotesEditorScreen(note: note)),
        ),
        onLongPress: () => _noteActions(note),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.description_outlined, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (note.snippet.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          note.snippet,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dateFormat.format(note.updatedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (note.date != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event, size: 13, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat(
                              'd MMM',
                              strings.locale,
                            ).format(note.date!),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Действия с папками
  // -------------------------------------------------------------------------

  Future<void> _folderActions(String path) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(strings.t('rename')),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(strings.t('deleteFolder')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      await _renameFolder(path);
    } else if (action == 'delete') {
      await _deleteFolder(path);
    }
  }

  Future<void> _createFolder() async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('newFolder')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: strings.t('folderName')),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.t('create')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = controller.text.trim();
    if (name.isEmpty || name.contains('/')) return;
    final path = AppState.joinFolder(_path, name);
    if (state.noteFolderPaths.contains(path)) {
      _showMessage(strings.t('folderExists'));
      return;
    }
    await state.createFolder(path);
    if (mounted) _enter(path);
  }

  Future<void> _renameFolder(String path) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final controller = TextEditingController(text: AppState.folderName(path));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: strings.t('folderName')),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.t('create')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = controller.text.trim();
    if (name.isEmpty || name.contains('/')) return;
    final newPath = AppState.joinFolder(AppState.folderParent(path), name);
    if (newPath == path) return;
    if (state.noteFolderPaths.contains(newPath)) {
      _showMessage(strings.t('folderExists'));
      return;
    }
    await state.renameFolder(path, newPath);
    if (!mounted) return;
    if (_path == path) {
      setState(() => _path = newPath);
    } else if (_path.startsWith('$path/')) {
      setState(() => _path = newPath + _path.substring(path.length));
    }
  }

  Future<void> _deleteFolder(String path) async {
    final state = context.read<AppState>();
    final ok = await state.deleteFolder(path);
    if (!mounted) return;
    if (!ok) _showMessage(state.strings.t('folderNotEmpty'));
  }

  // -------------------------------------------------------------------------
  // Действия с заметками
  // -------------------------------------------------------------------------

  Future<void> _noteActions(Note note) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(strings.t('moveToFolder')),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(strings.t('delete')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'move') {
      await _moveNote(note);
    } else if (action == 'delete') {
      await state.deleteNote(note);
    }
  }

  Future<void> _moveNote(Note note) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final paths = state.noteFolderPaths.toList()..sort();
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('moveToFolder')),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ListView(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.home_outlined, size: 20),
                title: Text(strings.t('notes')),
                trailing: note.folder.isEmpty
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final path in paths)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined, size: 20),
                  title: Text(path.replaceAll('/', ' / ')),
                  trailing: path == note.folder
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: Theme.of(ctx).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, path),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.t('cancel')),
          ),
        ],
      ),
    );
    if (chosen == null || chosen == note.folder || !mounted) return;
    await state.updateNote(note.copyWith(folder: chosen));
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _EmptyNotes extends StatelessWidget {
  final String message;

  const _EmptyNotes({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.note_add_outlined,
            size: 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

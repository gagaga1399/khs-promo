import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/note.dart';
import '../state/app_state.dart';
import 'notes_editor_screen.dart';
import 'notes_tasks_screen.dart';
import 'notes_trash_screen.dart';

/// Строка дерева: папка или заметка с уровнем вложенности.
class _TreeRow {
  final String path;
  final int depth;
  final bool isFolder;
  final Note? note;

  const _TreeRow.folder(this.path, this.depth) : isFolder = true, note = null;

  const _TreeRow.note(Note this.note, this.depth) : isFolder = false, path = '';
}

/// Панель заметок как проводник в Obsidian: плотное дерево папок и заметок,
/// сворачивание по тапу, контекстное меню по долгому нажатию, компактная
/// кнопка «Новая заметка» и подстраница «Задачи» из корня.
class NotesPanel extends StatefulWidget {
  /// [showAddButton] — показывать ли кнопку «Новая заметка» сверху.
  const NotesPanel({super.key, this.showAddButton = true});

  final bool showAddButton;

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  /// Раскрытые папки — по умолчанию дерево свёрнуто до корня, как в Obsidian.
  final Set<String> _expanded = <String>{};

  /// Папка, в которую создадутся новые заметки; `''` — корень.
  String _current = '';

  bool _isExpanded(String path) => _expanded.contains(path);

  void _select(String path) {
    setState(() {
      _current = path;
      if (path.isNotEmpty) _expanded.add(path);
    });
  }

  void _toggle(String path) {
    setState(() {
      _current = path;
      if (!_expanded.add(path)) _expanded.remove(path);
    });
  }

  /// Раскрыть папку и всех её предков — чтобы новое/перемещённое
  /// содержимое сразу оказалось видимым.
  void _reveal(String path) {
    while (path.isNotEmpty) {
      _expanded.add(path);
      path = AppState.folderParent(path);
    }
  }

  /// Плоский список строк дерева: на уровне — сначала папки, потом заметки,
  /// каждые по алфавиту (как в Obsidian).
  List<_TreeRow> _rows(AppState state) {
    final out = <_TreeRow>[];
    void walk(String path, int depth) {
      for (final folder in state.childFolders(path)) {
        out.add(_TreeRow.folder(folder, depth));
        if (_isExpanded(folder)) walk(folder, depth + 1);
      }
      final notes = state.notesInFolder(path).toList()
        ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      for (final note in notes) {
        out.add(_TreeRow.note(note, depth));
      }
    }

    walk('', 0);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final rows = _rows(state);
    final activeTasks = state.tasks.where((t) => !t.completed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Шапка проводника: «Новая заметка» + создать папку + корзина.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 0),
          child: Row(
            children: [
              if (widget.showAddButton)
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _createNote,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(strings.t('makeNewNote')),
                    ),
                  ),
                )
              else
                const Spacer(),
              IconButton(
                tooltip: strings.t('newFolder'),
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                onPressed: _createFolder,
              ),
              IconButton(
                tooltip: strings.t('trash'),
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotesTrashScreen()),
                ),
              ),
            ],
          ),
        ),
        if (_current.isNotEmpty) _breadcrumbs(context, strings),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              8,
              4,
              8,
              widget.showAddButton ? 16 : 104,
            ),
            children: [
              _tasksRow(
                context,
                strings,
                activeTasks,
                onOpen: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotesTasksScreen()),
                  );
                },
              ),
              for (final row in rows) _treeRow(context, row),
              if (rows.isEmpty)
                SizedBox(
                  height: 170,
                  child: _EmptyNotes(message: strings.t('noNotes')),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Хлебные крошки выбранной папки (где создастся новая заметка)
  // -------------------------------------------------------------------------

  Widget _breadcrumbs(BuildContext context, AppStrings strings) {
    final scheme = Theme.of(context).colorScheme;
    final segments = <Widget>[
      _crumbButton(strings.t('notes'), bold: false, onTap: () => _select('')),
    ];
    var cumulative = '';
    final parts = _current.split('/');
    for (var i = 0; i < parts.length; i++) {
      cumulative = i == 0 ? parts[i] : '$cumulative/${parts[i]}';
      final path = cumulative;
      segments.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Icon(
            Icons.chevron_right,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
      segments.add(
        _crumbButton(
          parts[i],
          bold: i == parts.length - 1,
          onTap: () => _select(path),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SizedBox(
        height: 24,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: segments),
        ),
      ),
    );
  }

  Widget _crumbButton(
    String label, {
    required bool bold,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
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
  // Строки дерева
  // -------------------------------------------------------------------------

  Widget _tasksRow(
    BuildContext context,
    AppStrings strings,
    int activeTasks, {
    required VoidCallback onOpen,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: Row(
              children: [
                const SizedBox(width: 16),
                const SizedBox(width: 4),
                Icon(Icons.checklist_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.t('tasks'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (activeTasks > 0)
                  Text(
                    '$activeTasks',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _treeRow(BuildContext context, _TreeRow row) {
    final key = ValueKey(
      row.isFolder ? 'folder:${row.path}' : 'note:${row.note!.id}',
    );
    // Появление строки: лёгкий подъём вверх и проявление.
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: _treeRowContent(context, row),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
    );
  }

  Widget _treeRowContent(BuildContext context, _TreeRow row) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = row.isFolder && _isExpanded(row.path);
    final selected = row.isFolder && _current == row.path;
    final label = row.isFolder
        ? AppState.folderName(row.path)
        : row.note!.title;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: row.isFolder
            ? () => _toggle(row.path)
            : () => _openNote(row.note!),
        onLongPress: row.isFolder
            ? () => _folderActions(row.path)
            : () => _noteActions(row.note!),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: EdgeInsets.only(left: 8 + row.depth * 14, right: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: row.isFolder
                        ? AnimatedRotation(
                            turns: expanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      row.isFolder
                          ? (expanded ? Icons.folder_open : Icons.folder)
                          : Icons.description_outlined,
                      key: ValueKey(
                        row.isFolder
                            ? (expanded ? 'folder_open' : 'folder')
                            : 'note',
                      ),
                      size: 16,
                      color: row.isFolder
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: row.isFolder
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Создание
  // -------------------------------------------------------------------------

  void _createNote() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotesEditorScreen(folder: _current)),
    );
  }

  void _openNote(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotesEditorScreen(note: note)),
    );
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
    final path = AppState.joinFolder(_current, name);
    if (state.noteFolderPaths.contains(path)) {
      _showMessage(strings.t('folderExists'));
      return;
    }
    await state.createFolder(path);
    if (!mounted) return;
    // Родители должны быть раскрыты, иначе папка не видна.
    setState(() => _reveal(path));
  }

  // -------------------------------------------------------------------------
  // Контекстное меню папки
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
    setState(() {
      if (_current == path) {
        _current = newPath;
      } else if (_current.startsWith('$path/')) {
        _current = newPath + _current.substring(path.length);
      }
      // Раскрытые папки старого пути переезжают на новый.
      final moved = _expanded
          .where((p) => p == path || p.startsWith('$path/'))
          .toList();
      for (final p in moved) {
        _expanded.remove(p);
        _expanded.add(newPath + p.substring(path.length));
      }
    });
  }

  Future<void> _deleteFolder(String path) async {
    final state = context.read<AppState>();
    final ok = await state.deleteFolder(path);
    if (!mounted) return;
    if (!ok) {
      _showMessage(state.strings.t('folderNotEmpty'));
      return;
    }
    setState(() {
      if (_current == path || _current.startsWith('$path/')) _current = '';
      _expanded.removeWhere((p) => p == path || p.startsWith('$path/'));
    });
  }

  // -------------------------------------------------------------------------
  // Контекстное меню заметки
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
    // Показываем заметку в новом месте: раскрываем целевую папку.
    if (mounted) {
      setState(() => _reveal(chosen));
    }
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
            size: 48,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

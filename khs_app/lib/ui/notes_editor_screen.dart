import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/note.dart';
import '../state/app_state.dart';

class NotesEditorScreen extends StatefulWidget {
  final Note? note;

  /// День для новой заметки дня (если не указан — сегодня).
  final DateTime? date;

  /// Текст из Obsidian, если открываем заметку дня без локальной копии.
  final String initialContent;

  const NotesEditorScreen({
    super.key,
    this.note,
    this.date,
    this.initialContent = '',
  });

  @override
  State<NotesEditorScreen> createState() => _NotesEditorScreenState();
}

class _NotesEditorScreenState extends State<NotesEditorScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late bool _isDaily;
  late DateTime _date;

  bool _dirty = false;

  bool get _isNew => widget.note == null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(
      text: widget.note?.content ?? widget.initialContent,
    );
    _isDaily = widget.note != null
        ? widget.note!.date != null
        : widget.date != null;
    _date =
        widget.note?.date ??
        widget.date ??
        DateTime(now.year, now.month, now.day);
    _titleController.addListener(_onEdit);
    _contentController.addListener(_onEdit);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onEdit() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_dirty) _autoSave();
    }
  }

  Future<void> _pickDate() async {
    final state = context.read<AppState>();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: Locale(state.locale),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
        _dirty = true;
      });
    }
  }

  /// Заголовок по умолчанию: первая строка текста или «Без названия».
  String _defaultTitle(AppStrings strings) {
    final firstLine = _contentController.text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isNotEmpty) {
      return firstLine.length <= 60 ? firstLine : firstLine.substring(0, 60);
    }
    return strings.t('defaultNoteTitle');
  }

  Future<bool> _saveCore({required bool showError}) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final title = _titleController.text.trim();
    final content = _contentController.text;
    if (title.isEmpty && content.trim().isEmpty) {
      if (showError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.t('noteTitleRequired'))));
      }
      return false;
    }
    final effectiveTitle = title.isEmpty ? _defaultTitle(strings) : title;
    if (_isNew) {
      await state.addNote(
        effectiveTitle,
        content,
        date: _isDaily ? _date : null,
      );
    } else {
      await state.updateNote(
        widget.note!.copyWith(title: effectiveTitle, content: content),
      );
    }
    _dirty = false;
    return true;
  }

  Future<void> _save() async {
    final saved = await _saveCore(showError: true);
    if (!saved || !mounted) return;
    Navigator.pop(context);
  }

  Future<void> _autoSave() async {
    if (!_dirty) return;
    await _saveCore(showError: false);
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('deleteNoteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              strings.t('delete'),
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await state.deleteNote(widget.note!);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final dateFormat = DateFormat('d MMMM yyyy', strings.locale);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _autoSave();
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? strings.t('createNote') : strings.t('editNote')),
          actions: [
            if (!_isNew)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: strings.t('save'),
              onPressed: _save,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_isNew)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(strings.t('dailyNote')),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.note_outlined, size: 16),
                      label: Text(strings.t('standaloneNote')),
                    ),
                  ],
                  selected: {_isDaily},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (s) => setState(() {
                    _isDaily = s.first;
                    _dirty = true;
                  }),
                ),
              ),
            if (_isDaily)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.event, size: 20),
                title: Text(
                  strings.t('noteDate'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                subtitle: Text(
                  dateFormat.format(_date),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: _isNew
                    ? TextButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.edit_calendar, size: 18),
                        label: Text(strings.t('chooseDate')),
                      )
                    : null,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: TextField(
                controller: _titleController,
                autofocus: _isNew,
                textInputAction: TextInputAction.next,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: strings.t('noteTitleHint'),
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: TextField(
                controller: _contentController,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                // Жёсткое ограничение скролла: выделение упирается в границы
                // окна и не «телепортируется» при прокрутке длинного текста.
                scrollPhysics: const ClampingScrollPhysics(),
                decoration: InputDecoration(
                  hintText: strings.t('noteContentHint'),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

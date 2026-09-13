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
  late final FocusNode _contentFocus;
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
    _contentFocus = FocusNode();
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
    _contentFocus.dispose();
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

  static int _lineStart(int offset, String text) =>
      text.lastIndexOf('\n', offset - 1) + 1;

  static int _lineEnd(int offset, String text) {
    final i = text.indexOf('\n', offset);
    return i == -1 ? text.length : i;
  }

  void _applyInline(String prefix, String suffix) {
    final c = _contentController;
    final text = c.text;
    var sel = c.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    final start = sel.isCollapsed ? sel.baseOffset : sel.start;
    final end = sel.isCollapsed ? sel.baseOffset : sel.end;
    final selected = text.substring(start, end);
    final newText =
        '${text.substring(0, start)}$prefix$selected$suffix${text.substring(end)}';
    final newOffset = start + prefix.length;
    c.value = TextEditingValue(
      text: newText,
      selection: selected.isEmpty
          ? TextSelection.collapsed(offset: newOffset)
          : TextSelection(
              baseOffset: newOffset,
              extentOffset: newOffset + selected.length,
            ),
      composing: TextRange.empty,
    );
    _contentFocus.requestFocus();
  }

  void _toggleLinePrefix(String prefix) {
    final c = _contentController;
    final text = c.text;
    var sel = c.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    final blockStart = _lineStart(sel.start, text);
    final blockEnd = _lineEnd(sel.isCollapsed ? sel.start : sel.end, text);
    final block = text.substring(blockStart, blockEnd);
    final lines = block.split('\n');
    var removing = true;
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      if (!l.startsWith(prefix)) {
        removing = false;
        break;
      }
    }
    final newLines = <String>[
      for (final l in lines)
        if (removing)
          (l.startsWith(prefix) ? l.substring(prefix.length) : l)
        else
          (l.trim().isEmpty ? l : '$prefix$l'),
    ];
    final newBlock = newLines.join('\n');
    final newText =
        '${text.substring(0, blockStart)}$newBlock${text.substring(blockEnd)}';
    final newOffset = (sel.baseOffset + (newBlock.length - block.length))
        .clamp(0, newText.length);
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
    _contentFocus.requestFocus();
  }

  void _toggleHeading(int level) {
    final prefix = '#${'#' * (level - 1)} ';
    final c = _contentController;
    final text = c.text;
    var sel = c.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    final blockStart = _lineStart(sel.start, text);
    final blockEnd = _lineEnd(sel.isCollapsed ? sel.start : sel.end, text);
    final block = text.substring(blockStart, blockEnd);
    final lines = block.split('\n');
    final newLines = <String>[
      for (final l in lines) _formatHeadingLine(l, level, prefix),
    ];
    final newBlock = newLines.join('\n');
    final newText =
        '${text.substring(0, blockStart)}$newBlock${text.substring(blockEnd)}';
    final newOffset = (sel.baseOffset + (newBlock.length - block.length))
        .clamp(0, newText.length);
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
    _contentFocus.requestFocus();
  }

  static String _formatHeadingLine(String line, int level, String prefix) {
    if (line.trim().isEmpty) return line;
    final trimmed = line.trimLeft();
    final matches = RegExp(r'^(#{1,6})\s').firstMatch(trimmed);
    if (matches == null) return '$prefix$line';
    if (matches.group(1)!.length == level) {
      return line.replaceFirst(trimmed, trimmed.substring(matches.group(0)!.length));
    }
    return line.replaceFirst(
      trimmed,
      '$prefix${trimmed.substring(matches.group(0)!.length)}',
    );
  }

  Widget _fmtButton(String tooltip, IconData icon, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
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
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _fmtButton(strings.t('fmtBold'), Icons.format_bold,
                      () => _applyInline('**', '**')),
                  _fmtButton(strings.t('fmtItalic'), Icons.format_italic,
                      () => _applyInline('*', '*')),
                  _fmtButton(strings.t('fmtStrike'), Icons.format_strikethrough,
                      () => _applyInline('~~', '~~')),
                  _fmtButton(strings.t('fmtCode'), Icons.code,
                      () => _applyInline('`', '`')),
                  _fmtButton(strings.t('fmtCodeBlock'), Icons.terminal,
                      () => _applyInline('\n```\n', '\n```\n')),
                  _fmtButton(strings.t('fmtH1'), Icons.looks_one_outlined,
                      () => _toggleHeading(1)),
                  _fmtButton(strings.t('fmtH2'), Icons.looks_two_outlined,
                      () => _toggleHeading(2)),
                  _fmtButton(strings.t('fmtH3'), Icons.looks_3_outlined,
                      () => _toggleHeading(3)),
                  _fmtButton(
                      strings.t('fmtBullet'), Icons.format_list_bulleted, () => _toggleLinePrefix('- ')),
                  _fmtButton(
                      strings.t('fmtNumList'), Icons.format_list_numbered, () => _toggleLinePrefix('1. ')),
                  _fmtButton(strings.t('fmtChecklist'), Icons.checklist,
                      () => _toggleLinePrefix('- [ ] ')),
                  _fmtButton(
                      strings.t('fmtQuote'), Icons.format_quote, () => _toggleLinePrefix('> ')),
                ],
              ),
            ),
            Expanded(
              child: TextField(
                controller: _contentController,
                focusNode: _contentFocus,
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

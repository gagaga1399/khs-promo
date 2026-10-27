import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../services/tracker_service.dart';
import '../state/app_state.dart';
import 'widgets/markdown_quill.dart';
import 'widgets/note_properties_editor.dart';

/// Заметка из хранилища Obsidian: свойства (frontmatter) и тело заметки
/// редактируются прямо здесь, как в Obsidian.
class VaultNoteViewerScreen extends StatefulWidget {
  const VaultNoteViewerScreen({
    super.key,
    required this.path,
    required this.title,
  });

  /// Абсолютный путь к markdown-файлу.
  final String path;
  final String title;

  @override
  State<VaultNoteViewerScreen> createState() => _VaultNoteViewerScreenState();
}

class _VaultNoteViewerScreenState extends State<VaultNoteViewerScreen> {
  QuillController? _controller;
  Object? _error;

  String _body = '';
  final List<NotePropertyDraft> _properties = [];
  int _nextId = 0;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.path);
      final text = await file.exists() ? await file.readAsString() : '';
      final parsed = TrackerService.parseFrontmatter(text);
      if (!mounted) return;
      setState(() {
        _body = parsed.body;
        _properties
          ..clear()
          ..addAll(
            parsed.properties.entries.map(
              (e) =>
                  NotePropertyDraft(id: _nextId++, key: e.key, value: e.value),
            ),
          );
        _controller = QuillController(
          document: markdownToQuillDocument(_body),
          selection: const TextSelection.collapsed(offset: 0),
        );
        _controller!.addListener(_onBodyChanged);
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _addProperty() {
    setState(() {
      _properties.add(NotePropertyDraft(id: _nextId++, key: '', value: ''));
      _dirty = true;
    });
  }

  void _removeProperty(NotePropertyDraft draft) {
    setState(() {
      _properties.remove(draft);
      _dirty = true;
    });
  }

  void _markDirty() {
    if (_dirty) {
      setState(() {});
    } else {
      setState(() => _dirty = true);
    }
  }

  void _onBodyChanged() => _markDirty();

  Future<void> _save({bool notify = true}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final map = <String, Object?>{};
      for (final draft in _properties) {
        final key = draft.key.trim();
        if (key.isEmpty) continue;
        map[key] = draft.value;
      }
      final frontmatter = TrackerService.buildFrontmatter(map);
      final body = _controller == null
          ? _body
          : quillDocumentToMarkdown(_controller!.document);
      final content = frontmatter.isEmpty ? body : '$frontmatter$body';
      await File(widget.path).writeAsString(content, encoding: utf8);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<AppState>().strings.t('vaultNoteSaved')),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e;
      });
    }
  }

  Future<void> _deleteNote() async {
    final strings = context.read<AppState>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(
          strings
              .t('vaultNoteDeleteConfirm')
              .replaceFirst('{name}', widget.title),
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
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await File(widget.path).delete();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('vaultNoteDeleteFailed'))),
      );
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(strings.t('vaultNoteDeleted'))),
    );
    setState(() => _dirty = false);
    navigator.pop(true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppState>().strings;
    final controller = _controller;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _save(notify: false);
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: strings.t('vaultNoteDelete'),
              onPressed: _deleteNote,
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: strings.t('save'),
                onPressed: _dirty ? () => _save() : null,
              ),
          ],
        ),
        body: _error != null
            ? const Center(child: Text('Не удалось открыть заметку'))
            : controller == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NotePropertiesEditor(
                      strings: strings,
                      properties: _properties,
                      onChanged: _markDirty,
                      onAdd: _addProperty,
                      onRemove: _removeProperty,
                    ),
                    const Divider(height: 1),
                    QuillSimpleToolbar(
                      controller: controller,
                      config: const QuillSimpleToolbarConfig(
                        multiRowsDisplay: true,
                        showFontFamily: false,
                        showFontSize: false,
                        showUnderLineButton: false,
                        showColorButton: false,
                        showBackgroundColorButton: false,
                        showClearFormat: true,
                        showAlignmentButtons: false,
                        showHeaderStyle: true,
                        showListNumbers: true,
                        showListBullets: true,
                        showListCheck: true,
                        showCodeBlock: true,
                        showQuote: true,
                        showIndent: false,
                        showLink: true,
                        showUndo: true,
                        showRedo: true,
                        showSearchButton: false,
                        showSubscript: false,
                        showSuperscript: false,
                        showStrikeThrough: true,
                        showInlineCode: true,
                      ),
                    ),
                    const Divider(height: 1),
                    QuillEditor.basic(
                      controller: controller,
                      config: const QuillEditorConfig(
                        expands: false,
                        scrollable: false,
                        autoFocus: false,
                        scrollPhysics: ClampingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

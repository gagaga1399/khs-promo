import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/note_template.dart';
import '../services/tracker_service.dart';
import '../state/app_state.dart';
import 'widgets/note_properties_editor.dart';

/// Результат редактора шаблона: сохранённый шаблон либо удаление.
class NoteTemplateEditResult {
  const NoteTemplateEditResult.saved(this.template) : deleted = false;

  const NoteTemplateEditResult.deleted() : template = null, deleted = true;

  final NoteTemplate? template;
  final bool deleted;
}

/// Редактор пользовательского шаблона заметки: название, тело и свойства
/// по умолчанию. Возвращает [NoteTemplateEditResult] через `Navigator.pop`.
class NoteTemplateEditorScreen extends StatefulWidget {
  const NoteTemplateEditorScreen({super.key, this.existing});

  /// Существующий шаблон для правки либо null при создании нового.
  final NoteTemplate? existing;

  @override
  State<NoteTemplateEditorScreen> createState() =>
      _NoteTemplateEditorScreenState();
}

class _NoteTemplateEditorScreenState extends State<NoteTemplateEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _body;
  final List<NotePropertyDraft> _properties = [];
  int _nextId = 0;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _body = TextEditingController(text: existing?.body ?? '');
    if (existing != null) {
      for (final property in existing.properties) {
        _properties.add(
          NotePropertyDraft(
            id: _nextId++,
            key: property.key,
            value: property.value,
          ),
        );
      }
    }
    _name.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  void _addProperty() {
    setState(() {
      _properties.add(NotePropertyDraft(id: _nextId++, key: '', value: ''));
    });
  }

  void _removeProperty(NotePropertyDraft draft) {
    setState(() => _properties.remove(draft));
  }

  void _save() {
    final strings = context.read<AppState>().strings;
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.t('noteTemplateNameRequired'))));
      return;
    }
    final template = NoteTemplate(
      id:
          widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      body: _body.text,
      properties: [
        for (final draft in _properties)
          if (draft.key.trim().isNotEmpty)
            NotePropertySpec(key: draft.key.trim(), value: draft.value),
      ],
    );
    Navigator.of(context).pop(NoteTemplateEditResult.saved(template));
  }

  Future<void> _delete() async {
    final strings = context.read<AppState>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(strings.t('noteTemplateDeleteConfirm')),
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
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const NoteTemplateEditResult.deleted());
    }
  }

  /// Импортирует шаблон из папки шаблонов Obsidian: заполняет имя, тело и
  /// свойства из выбранного markdown-файла хранилища.
  Future<void> _importFromObsidian() async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final obsidian = state.obsidian;
    if (!obsidian.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.t('trackerNoVault'))),
      );
      return;
    }
    final files = await obsidian.listTemplates();
    if (!mounted) return;
    if (files.isEmpty) {
      final hasFolder = await obsidian.templateFolder();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.t(
              hasFolder == null
                  ? 'noteTemplateImportNone'
                  : 'noteTemplateImportEmpty',
            ),
          ),
        ),
      );
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(strings.t('noteTemplateImportTitle')),
        children: [
          for (final file in files)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, file),
              child: Text(
                p.basenameWithoutExtension(file),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final content = await obsidian.readRelative(picked);
    if (content == null || !mounted) return;
    final parsed = TrackerService.parseFrontmatter(content);
    setState(() {
      _name.text = p.basenameWithoutExtension(picked);
      _body.text = parsed.body;
      _properties.clear();
      for (final entry in parsed.properties.entries) {
        _properties.add(
          NotePropertyDraft(id: _nextId++, key: entry.key, value: entry.value),
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.t('noteTemplateImported'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppState>().strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.t(_isNew ? 'noteTemplateNew' : 'noteTemplateEdit')),
        actions: [
          IconButton(
            tooltip: strings.t('noteTemplateImport'),
            icon: const Icon(Icons.download_outlined),
            onPressed: _importFromObsidian,
          ),
          if (!_isNew)
            IconButton(
              tooltip: strings.t('noteTemplateDelete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          IconButton(
            tooltip: strings.t('noteTemplateSave'),
            icon: const Icon(Icons.check),
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                key: const ValueKey('note_template_name'),
                controller: _name,
                autofocus: _isNew,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: strings.t('noteTemplateName'),
                  hintText: strings.t('noteTemplateNameHint'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                key: const ValueKey('note_template_body'),
                controller: _body,
                minLines: 6,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: strings.t('noteTemplateBody'),
                  hintText: strings.t('noteTemplateBodyHint'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            NotePropertiesEditor(
              strings: strings,
              properties: _properties,
              onChanged: () {},
              onAdd: _addProperty,
              onRemove: _removeProperty,
            ),
          ],
        ),
      ),
    );
  }
}

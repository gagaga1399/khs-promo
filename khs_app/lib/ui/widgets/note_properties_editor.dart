import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../models/tracker_entry.dart';
import '../../services/tracker_service.dart';

/// Черновик одного свойства заметки во время редактирования.
class NotePropertyDraft {
  NotePropertyDraft({
    required this.id,
    required this.key,
    required this.value,
    TrackerPropertyKind? kind,
  }) : kind = kind ?? TrackerService.kindOf(value);

  final int id;
  String key;
  Object? value;
  TrackerPropertyKind kind;
}

/// Пересчитывает значение при смене типа свойства.
Object? convertPropertyValue(Object? value, TrackerPropertyKind to) {
  switch (to) {
    case TrackerPropertyKind.boolean:
      return TrackerService.isDone(value);
    case TrackerPropertyKind.number:
      if (value is num) return value;
      return num.tryParse(
            TrackerService.displayValue(value).replaceAll(',', '.'),
          ) ??
          0;
    case TrackerPropertyKind.date:
      final text = TrackerService.displayValue(value);
      if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}').hasMatch(text)) return text;
      return _isoDate(DateTime.now());
    case TrackerPropertyKind.list:
      if (value is List) return value;
      if (value == null) return <Object?>[];
      return <Object?>[value];
    case TrackerPropertyKind.text:
      if (value is List) {
        return value.map(TrackerService.displayValue).join(', ');
      }
      if (value is bool) return value ? 'true' : 'false';
      return value == null ? '' : TrackerService.displayValue(value);
  }
}

String _isoDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Редактор свойств (frontmatter) заметки в стиле Obsidian.
class NotePropertiesEditor extends StatelessWidget {
  const NotePropertiesEditor({
    super.key,
    required this.strings,
    required this.properties,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
  });

  final AppStrings strings;
  final List<NotePropertyDraft> properties;
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final ValueChanged<NotePropertyDraft> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
          child: Row(
            children: [
              Icon(Icons.tune, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                strings.t('vaultProps'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: strings.t('vaultPropAdd'),
                icon: const Icon(Icons.add, size: 20),
                onPressed: onAdd,
              ),
            ],
          ),
        ),
        if (properties.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 0, 16, 12),
            child: Text(
              strings.t('vaultPropNone'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          )
        else
          for (final draft in properties)
            _PropertyRow(
              key: ValueKey(draft.id),
              draft: draft,
              strings: strings,
              onChanged: onChanged,
              onRemove: onRemove,
            ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _PropertyRow extends StatefulWidget {
  const _PropertyRow({
    super.key,
    required this.draft,
    required this.strings,
    required this.onChanged,
    required this.onRemove,
  });

  final NotePropertyDraft draft;
  final AppStrings strings;
  final VoidCallback onChanged;
  final ValueChanged<NotePropertyDraft> onRemove;

  @override
  State<_PropertyRow> createState() => _PropertyRowState();
}

class _PropertyRowState extends State<_PropertyRow> {
  late final TextEditingController _keyCtrl;
  TextEditingController? _valueCtrl;
  TrackerPropertyKind? _syncedKind;

  bool get _russian => widget.strings.locale == 'ru';

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.draft.key);
    _syncValue();
  }

  @override
  void didUpdateWidget(covariant _PropertyRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.draft.kind != _syncedKind) _syncValue();
  }

  void _syncValue() {
    final kind = widget.draft.kind;
    _syncedKind = kind;
    if (kind == TrackerPropertyKind.boolean) {
      _valueCtrl?.dispose();
      _valueCtrl = null;
      return;
    }
    _valueCtrl ??= TextEditingController();
    _valueCtrl!.text = _textFor(widget.draft.value, kind);
  }

  String _textFor(Object? value, TrackerPropertyKind kind) {
    if (value == null) return '';
    if (value is List) {
      return value.map(TrackerService.displayValue).join(', ');
    }
    if (kind == TrackerPropertyKind.date) return '$value';
    return TrackerService.displayValue(value);
  }

  void _onValueText(String text) {
    switch (widget.draft.kind) {
      case TrackerPropertyKind.number:
        widget.draft.value = num.tryParse(text.replaceAll(',', '.')) ?? text;
        break;
      case TrackerPropertyKind.list:
        widget.draft.value = text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        break;
      default:
        widget.draft.value = text;
    }
    widget.onChanged();
  }

  void _changeType(TrackerPropertyKind kind) {
    if (kind == widget.draft.kind) return;
    widget.draft.value = convertPropertyValue(widget.draft.value, kind);
    widget.draft.kind = kind;
    _syncValue();
    widget.onChanged();
    setState(() {});
  }

  Future<void> _pickDate() async {
    final current =
        TrackerService.dateFromValue(widget.draft.value) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    widget.draft.value = _isoDate(picked);
    _valueCtrl?.text = widget.draft.value as String;
    widget.onChanged();
  }

  IconData _iconFor(TrackerPropertyKind kind) => switch (kind) {
    TrackerPropertyKind.boolean => Icons.check_box_outlined,
    TrackerPropertyKind.number => Icons.numbers,
    TrackerPropertyKind.date => Icons.calendar_today_outlined,
    TrackerPropertyKind.list => Icons.list,
    TrackerPropertyKind.text => Icons.text_fields,
  };

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PopupMenuButton<TrackerPropertyKind>(
            tooltip: widget.strings.t('vaultPropType'),
            onSelected: _changeType,
            itemBuilder: (context) => [
              for (final kind in TrackerPropertyKind.values)
                PopupMenuItem<TrackerPropertyKind>(
                  value: kind,
                  child: Row(
                    children: [
                      Icon(
                        _iconFor(kind),
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(kind.label(_russian)),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _iconFor(widget.draft.kind),
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _keyCtrl,
              onChanged: (v) {
                widget.draft.key = v;
                widget.onChanged();
              },
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.strings.t('vaultPropName'),
                isDense: true,
                border: const UnderlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: _valueField(context)),
          IconButton(
            tooltip: widget.strings.t('vaultPropDelete'),
            icon: Icon(Icons.close, size: 16, color: scheme.onSurfaceVariant),
            onPressed: () => widget.onRemove(widget.draft),
          ),
        ],
      ),
    );
  }

  Widget _valueField(BuildContext context) {
    final draft = widget.draft;
    if (draft.kind == TrackerPropertyKind.boolean) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Switch(
          value: draft.value == true,
          onChanged: (v) {
            draft.value = v;
            widget.onChanged();
            setState(() {});
          },
        ),
      );
    }
    final isDate = draft.kind == TrackerPropertyKind.date;
    return TextField(
      controller: _valueCtrl,
      onChanged: _onValueText,
      keyboardType: draft.kind == TrackerPropertyKind.number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.strings.t('vaultPropValue'),
        isDense: true,
        border: const UnderlineInputBorder(),
        suffixIcon: isDate
            ? IconButton(
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                onPressed: _pickDate,
              )
            : null,
      ),
    );
  }
}

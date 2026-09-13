import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Размер и межстрочный интервал, как у поля ввода заметок.
const double kNoteEditorFontSize = 15.0;
const double kNoteEditorLineHeight = 1.5;

/// Стиль предпросмотра, максимально близкий к обычному полю ввода:
/// тот же размер/цвет текста, аккуратные заголовки и компактные отступы.
MarkdownStyleSheet notePreviewStyle(ThemeData theme) {
  final scheme = theme.colorScheme;
  final base = TextStyle(
    fontSize: kNoteEditorFontSize,
    height: kNoteEditorLineHeight,
    color: scheme.onSurface,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: base,
    h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.bold, height: 1.25),
    h2: base.copyWith(fontSize: 19, fontWeight: FontWeight.bold, height: 1.3),
    h3: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
    h4: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
    h5: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    h6: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    blockquote: base.copyWith(
      color: scheme.onSurfaceVariant,
      fontStyle: FontStyle.normal,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
    blockquoteDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      border: Border(
        left: BorderSide(
          color: scheme.primary.withValues(alpha: 0.4),
          width: 3,
        ),
      ),
    ),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.4,
      color: scheme.onSurface,
      backgroundColor: scheme.surfaceContainerHighest,
    ),
    codeblockPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    blockSpacing: 8,
    listIndent: 22,
    listBullet: base.copyWith(color: scheme.primary),
    listBulletPadding: const EdgeInsets.only(left: 14),
    checkbox: base,
  );
}

/// Прочитанный markdown, выглядит так же, как текст в поле ввода.
class NoteMarkdownPreview extends StatelessWidget {
  const NoteMarkdownPreview({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: notePreviewStyle(Theme.of(context)),
    );
  }
}
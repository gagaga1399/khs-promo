import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'notes_editor_screen.dart';
import 'notes_trash_screen.dart';

/// Режим «Дизайн» — панель заметок (центр экрана).
class NotesPanel extends StatelessWidget {
  /// [showAddButton] — показывать ли крупную кнопку «Создать заметку» сверху.
  /// Кнопка одна и на телефоне, и на десктопе: отдельной плавающей нет.
  const NotesPanel({super.key, this.showAddButton = true});

  final bool showAddButton;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final notes = state.notes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.t('notes'),
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
            ],
          ),
        ),
        if (showAddButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () {
                  final existing = state.notesForDate(state.selectedDate);
                  if (existing.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NotesEditorScreen(note: existing.first),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            NotesEditorScreen(date: state.selectedDate),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(strings.t('makeNewNote')),
              ),
            ),
          ),
        Expanded(
          child: notes.isEmpty
              ? _EmptyNotes(message: strings.t('noNotes'))
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    showAddButton ? 16 : 104,
                  ),
                  itemCount: notes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final note = notes[i];
                    final dateFormat = DateFormat(
                      'd MMM, HH:mm',
                      strings.locale,
                    );
                    return Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotesEditorScreen(note: note),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
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
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  if (note.date != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.event,
                                            size: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            DateFormat(
                                              'd MMM',
                                              strings.locale,
                                            ).format(note.date!),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
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
                  },
                ),
        ),
      ],
    );
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

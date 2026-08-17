import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';

/// Корзина (история удалённых заметок): восстановить или удалить навсегда.
class NotesTrashScreen extends StatelessWidget {
  const NotesTrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final deleted = state.deletedNotes;

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('trash'))),
      body: deleted.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_sweep_outlined,
                    size: 64,
                    color: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.t('trashEmpty'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: deleted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final note = deleted[i];
                final dateFormat = DateFormat('d MMM, HH:mm', strings.locale);
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      note.snippet.isNotEmpty
                          ? note.snippet
                          : dateFormat.format(note.updatedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: strings.t('restore'),
                          icon: const Icon(Icons.restore, size: 20),
                          onPressed: () => state.restoreNote(note),
                        ),
                        IconButton(
                          tooltip: strings.t('deleteForever'),
                          icon: Icon(
                            Icons.delete_forever_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => _deleteForever(context, state, note),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _deleteForever(
    BuildContext context,
    AppState state,
    Note note,
  ) async {
    final strings = state.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('deleteForeverConfirm')),
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
      await state.deleteNoteForever(note);
    }
  }
}

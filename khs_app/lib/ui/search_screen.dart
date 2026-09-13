import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../localization/app_strings.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../state/app_state.dart';
import 'task_edit_screen.dart';
import 'widgets/task_tile.dart';

/// Глобальный поиск по задачам и заметкам.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  /// Открывает поиск с анимированным переходом.
  static void open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SearchScreen(),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _matchesTask(Task t, String q) {
    return t.title.toLowerCase().contains(q);
  }

  bool _matchesNote(Note n, String q) {
    return n.title.toLowerCase().contains(q) ||
        n.content.toLowerCase().contains(q);
  }

  Future<void> _confirmDeleteTasks(
    AppState state,
    AppStrings strings,
    List<Task> tasks,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_outlined),
        title: Text(strings.t('deleteConfirm')),
        content: Text(
          '${tasks.length}: ${tasks.map((t) => t.title).join(', ')}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
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
    if (ok != true) return;
    for (final t in tasks) {
      await state.deleteTask(t);
    }
  }

  Future<void> _confirmDeleteNote(
    AppState state,
    AppStrings strings,
    Note note,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('deleteConfirm')),
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
    if (ok == true) await state.deleteNote(note);
  }

  void _showNote(AppStrings strings, Note note) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.sticky_note_2_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(note.title, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            note.content.trim().isEmpty ? '—' : note.content,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.t('ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final q = _controller.text.trim().toLowerCase();

    final List<Task> matchedTasks = q.isEmpty
        ? const []
        : state.tasks.where((t) => _matchesTask(t, q)).toList();
    final List<Note> matchedNotes = q.isEmpty
        ? const []
        : state.notes.where((n) => _matchesNote(n, q)).toList();
    final hasResults = matchedTasks.isNotEmpty || matchedNotes.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: q.isEmpty
                        ? Colors.transparent
                        : scheme.primary.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: strings.t('searchHint'),
                    prefixIcon: AnimatedRotation(
                      turns: q.isEmpty ? 0 : 0.15,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      child: const Icon(Icons.search),
                    ),
                    suffixIcon: q.isEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: strings.t('cancel'),
                            onPressed: () => Navigator.pop(context),
                          )
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: strings.t('cancel'),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                              _focusNode.requestFocus();
                            },
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      axisAlignment: -1,
                      child: child,
                    ),
                  );
                },
                child: q.isEmpty
                    ? _EmptyResult(
                        key: const ValueKey('idle'),
                        icon: Icons.manage_search,
                        text: strings.t('searchHint'),
                        animated: true,
                      )
                    : !hasResults
                    ? _EmptyResult(
                        key: const ValueKey('none'),
                        icon: Icons.search_off,
                        text: strings.t('searchNoResults'),
                        animated: true,
                      )
                    : ListView(
                        key: const ValueKey('results'),
                        children: [
                          if (matchedTasks.isNotEmpty) ...[
                            _SectionHeader(title: strings.t('tasks')),
                            for (var i = 0; i < matchedTasks.length; i++)
                              _TaskResult(
                                task: matchedTasks[i],
                                onToggle: (v) => state.toggleCompleted(
                                  matchedTasks[i],
                                ),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TaskEditScreen(
                                      task: matchedTasks[i],
                                    ),
                                  ),
                                ),
                                onDelete: () => _confirmDeleteTasks(
                                  state,
                                  strings,
                                  [matchedTasks[i]],
                                ),
                              ),
                          ],
                          if (matchedNotes.isNotEmpty) ...[
                            _SectionHeader(title: strings.t('notes')),
                            for (var i = 0; i < matchedNotes.length; i++)
                              _NoteResult(
                                note: matchedNotes[i],
                                onTap: () => _showNote(strings, matchedNotes[i]),
                                onDelete: () =>
                                    _confirmDeleteNote(state, strings, matchedNotes[i]),
                              ),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool animated;

  const _EmptyResult({
    super.key,
    required this.icon,
    required this.text,
    this.animated = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: animated
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: _buildBody(scheme),
            )
          : _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 54, color: scheme.outline),
        const SizedBox(height: 12),
        Text(
          text,
          style: TextStyle(color: scheme.outline, fontSize: 15),
        ),
      ],
    );
  }
}

class _TaskResult extends StatelessWidget {
  final Task task;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _TaskResult({
    required this.task,
    this.onToggle,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppState>().strings;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) =>
          Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child)),
      child: TaskTile(
        task: task,
        strings: strings,
        onToggle: (v) => onToggle?.call(v),
        onTap: onTap ?? () {},
        onDelete: onDelete ?? () {},
      ),
    );
  }
}

class _NoteResult extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NoteResult({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppState>().strings;
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) =>
          Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child)),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          leading: Icon(Icons.sticky_note_2_outlined, color: scheme.primary),
          title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            note.content.replaceAll('\n', ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: strings.t('delete'),
            onPressed: onDelete,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
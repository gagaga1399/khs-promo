import 'package:flutter/material.dart';

import '../glass_bottom_bar.dart';
import '../search.dart';
import '../settings.dart';
import 'folders_screen.dart';
import 'library_screen.dart';
import 'notes_screen.dart';
import 'search_screen.dart';

/// Главный экран с 4 вкладками внизу: Библиотека, Заметки, Папки, Поиск.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    final catalogs = SettingsStore.instance.oo.catalogs.isEmpty
        ? SearchService.defaultCatalogs
        : SettingsStore.instance.oo.catalogs;
    _tabs = [
      const LibraryScreen(),
      const NotesScreen(),
      SearchScreen(catalogs: catalogs),
      const FoldersScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Собственной шапки нет: читалка открывается внутри хаба, AppBar остаётся
    // от хаба — как у KHS Tasks. Снизу тот же GlassBottomBar.
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: GlassBottomBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          GlassNavItem(
            icon: Icons.library_books_outlined,
            activeIcon: Icons.library_books,
            label: 'Библиотека',
          ),
          GlassNavItem(
            icon: Icons.bookmarks_outlined,
            activeIcon: Icons.bookmarks,
            label: 'Заметки',
          ),
          GlassNavItem(
            icon: Icons.search_outlined,
            activeIcon: Icons.search,
            label: 'Поиск',
          ),
          GlassNavItem(
            icon: Icons.folder_outlined,
            activeIcon: Icons.folder,
            label: 'Файлы',
          ),
        ],
      ),
    );
  }
}

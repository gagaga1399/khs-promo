import 'package:flutter/material.dart';

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
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Библиотека',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks),
            label: 'Заметки',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Поиск',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Файлы',
          ),
        ],
      ),
    );
  }
}

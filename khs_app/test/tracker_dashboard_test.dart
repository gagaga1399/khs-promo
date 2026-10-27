import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:khs/services/tracker_service.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/tracker_dashboard_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khs_tracker_dash');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> writeNote(String name, String content) async {
    final dir = Directory('${tempDir.path}/даты');
    await dir.create(recursive: true);
    await File('${dir.path}/$name').writeAsString(content);
  }

  testWidgets('дашборд строится по заметкам хранилища', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await writeNote(
        '2026-10-10.md',
        '---\nчтение: true\nсамоощущение: 70\nпродуктивность: 60\n'
            'желание действовать: true\nзарядка: false\n---\n\n'
            '- [x] сделано\nпривет мир\n',
      );
      await writeNote(
        '2026-10-11.md',
        '---\nчтение: false\nсамоощущение: 40\nпродуктивность: 30\n'
            'желание действовать: false\nзарядка: true\n---\n\n'
            '- [ ] нет\n- [x] да\n',
      );
    });

    final tracker = TrackerService(vaultPathProvider: () => tempDir.path);
    await tester.runAsync(() => tracker.refresh());

    final state = AppState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<TrackerService>.value(value: tracker),
        ],
        child: const MaterialApp(home: TrackerDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Обзор трекеров'), findsOneWidget);
    expect(find.text('Привычки по месяцам'), findsOneWidget);
    // Блок «Деятельность и исполнительность» вынесен в самый конец дашборда,
    // поэтому до него нужно прокрутить список.
    await tester.scrollUntilVisible(
      find.text('Деятельность и исполнительность'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Деятельность и исполнительность'), findsOneWidget);
  });
}

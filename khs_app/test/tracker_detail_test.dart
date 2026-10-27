import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:khs/models/tracker_entry.dart';
import 'package:khs/services/tracker_service.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/tracker_charts.dart';
import 'package:khs/ui/tracker_detail_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khs_tracker_detail');
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

  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  testWidgets('детальный экран метрики-оценки: сетка и видимый график', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    await tester.runAsync(() async {
      await writeNote('${iso(yesterday)}.md', '---\nсамоощущение: 40\n---\n');
      await writeNote('${iso(today)}.md', '---\nсамоощущение: 70\n---\n');
    });

    final tracker = TrackerService(vaultPathProvider: () => tempDir.path);
    await tester.runAsync(() => tracker.refresh());

    final state = AppState();
    const prop = TrackerProperty(
      name: 'самоощущение',
      kind: TrackerPropertyKind.number,
      filled: 2,
      total: 2,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<TrackerService>.value(value: tracker),
        ],
        child: const MaterialApp(home: TrackerDetailScreen(property: prop)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ValueYearGrid), findsOneWidget);
    final chart = find.byType(MetricChart);
    expect(chart, findsOneWidget);
    expect(tester.getSize(chart).width, greaterThan(100));
    expect(tester.takeException(), isNull);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:khs/services/license_key.dart';
import 'package:khs/services/tracker_service.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/glass_bottom_bar.dart';
import 'package:khs/ui/tracker_dashboard_screen.dart';
import 'package:khs/ui/tracker_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khs_tracker_nav');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('трекеры: нижняя панель переключает разделы внутри приложения', (
    tester,
  ) async {
    final tracker = TrackerService(vaultPathProvider: () => tempDir.path);
    await tester.runAsync(() => tracker.refresh());
    final state = AppState();
    // Раздел «Трекеры» закрыт по умолчанию — открываем по ключу для теста.
    await state.unlockTracker(LicenseKey.valid);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<TrackerService>.value(value: tracker),
        ],
        child: const MaterialApp(home: TrackerHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kGlassNavCapsuleKey), findsOneWidget);
    expect(find.byType(TrackerDashboardScreen), findsNothing);

    await tester.tap(find.byKey(const Key('glass-nav-slot-label-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(TrackerHomeScreen), findsOneWidget);
    expect(find.byType(TrackerDashboardScreen), findsOneWidget);
  });
}

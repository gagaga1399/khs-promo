import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/tracker_entry.dart';
import 'package:khs/services/tracker_service.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/tracker_settings_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('настройки трекеров показывают хранилище, профили и трекеры', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState();
    final tracker = TrackerService(vaultPathProvider: () => '');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<TrackerService>.value(value: tracker),
        ],
        child: const MaterialApp(home: Scaffold(body: TrackerSettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Профили'), findsOneWidget);
    expect(find.text('Активный профиль'), findsOneWidget);
    expect(find.text('Добавить профиль'), findsOneWidget);
    expect(find.text('Трекеры'), findsWidgets);
    expect(find.text('Добавить трекер'), findsWidgets);
    expect(find.text('Сохранить путь'), findsOneWidget);
    expect(find.text('День рождения'), findsOneWidget);
  });

  test('день рождения сохраняется и сбрасывается', () async {
    final state = AppState();
    expect(state.birthday, isNull);

    await state.setBirthday(DateTime(2010, 3, 19, 13, 30));
    expect(state.birthday, DateTime(2010, 3, 19));

    await state.setBirthday(null);
    expect(state.birthday, isNull);
  });

  test('профили: добавить/удалить, свои трекеры добавить/убрать', () async {
    final state = AppState();

    await state.addCustomTracker('тренировка', TrackerPropertyKind.boolean);
    expect(state.activeTrackerProfile.custom.length, 1);

    await state.removeTracker('тренировка');
    expect(state.activeTrackerProfile.custom, isEmpty);

    await state.addTrackerProfile('Аня');
    expect(state.trackerProfiles.length, 2);
    expect(state.activeTrackerProfile.name, 'Аня');

    await state.deleteTrackerProfile(state.activeTrackerProfile.id);
    expect(state.trackerProfiles.length, 1);
  });
}

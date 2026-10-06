import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/download_progress.dart';

void main() {
  group('формат размера', () {
    test('переводит байты в КБ и МБ', () {
      expect(formatBytes(512), '512 Б');
      expect(formatBytes(2048), '2 КБ');
      expect(formatBytes(5 * 1024 * 1024), '5.0 МБ');
      expect(formatBytes(82325611), '78.5 МБ');
    });
  });

  group('прогресс', () {
    test('без известной длины доля неизвестна, а не ноль', () {
      const s = DownloadSample(1024, 0, 0);
      expect(s.fraction, isNull);
    });

    test('доля считается по полученному и общему', () {
      expect(const DownloadSample(50, 100, 0).fraction, 0.5);
      expect(const DownloadSample(100, 100, 0).fraction, 1.0);
    });

    test('доля не выходит за единицу на переизбытке', () {
      expect(const DownloadSample(150, 100, 0).fraction, 1.0);
    });

    test('первый отсчёт сразу попадает в значение', () {
      final p = DownloadProgress();
      addTearDown(p.dispose);
      p(1024, 4096);
      expect(p.value.value.received, 1024);
      expect(p.value.value.total, 4096);
      expect(p.value.value.fraction, 0.25);
    });

    test('скорость не считается по первому мгновенному куску', () {
      // Первый кучок приходит без предыдущей точки отсчёта: если взять
      // мгновенную скорость сразу, на экране мелькнёт неверное число.
      final p = DownloadProgress();
      addTearDown(p.dispose);
      p(1 << 30, 1 << 31);
      expect(p.value.value.bytesPerSecond, 0);
    });
  });

  group('диалог', () {
    Future<DownloadProgress> pumpDialog(
      WidgetTester tester,
      DownloadProgress progress,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadProgressDialog(
              fileName: 'khs-1.2.32.apk',
              progress: progress,
              title: 'Загрузка',
            ),
          ),
        ),
      );
      return progress;
    }

    testWidgets('показывает процент, размер и скорость', (tester) async {
      final p = DownloadProgress();
      await pumpDialog(tester, p);
      addTearDown(p.dispose);

      expect(find.text('Загрузка'), findsOneWidget);
      expect(find.text('khs-1.2.32.apk'), findsOneWidget);

      // Пока длина неизвестна, процент не показываем выдуманный ноль.
      p(1024, 0);
      await tester.pump();
      expect(find.text('…'), findsOneWidget);

      p(5 * 1024 * 1024, 10 * 1024 * 1024);
      await tester.pump();
      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('5.0 МБ из 10.0 МБ'), findsOneWidget);
    });

    testWidgets('индикатор едет по доле скачанного', (tester) async {
      final p = DownloadProgress();
      await pumpDialog(tester, p);
      addTearDown(p.dispose);

      p(2048, 4096);
      await tester.pump();
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.5);
    });
  });
}

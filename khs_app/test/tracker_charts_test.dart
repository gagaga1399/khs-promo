import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/tracker_charts.dart';
import 'package:provider/provider.dart';

Widget _host(Widget child) => ChangeNotifierProvider<AppState>(
  create: (_) => AppState(),
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('HabitHeatmap растягивается по ширине, а не сжимается в 0', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 84,
                child: HabitHeatmap(
                  end: DateTime(2026, 10, 15),
                  weeks: 26,
                  values: const {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final size = tester.getSize(
      find.descendant(
        of: find.byType(HabitHeatmap),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(size.width, greaterThan(100));
    expect(size.height, greaterThan(0));
  });

  testWidgets('ValueYearGrid рисует год из квадратиков', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 320,
          child: ValueYearGrid(
            end: DateTime(2026, 10, 15),
            values: {
              DateTime(2026, 10, 10): 30,
              DateTime(2026, 10, 11): 70,
              DateTime(2026, 10, 12): 50,
            },
            valueColor: (v) => v >= 50
                ? const Color(0xFF2B8A3E)
                : const Color(0xFFE03131),
          ),
        ),
      ),
    );

    expect(find.byType(ValueYearGrid), findsOneWidget);
    expect(find.text('окт 26'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ValueYearGrid: тап по квадратику дня вызывает onTapDay', (
    tester,
  ) async {
    DateTime? tapped;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 320,
          child: ValueYearGrid(
            end: DateTime(2026, 10, 15),
            values: {DateTime(2026, 10, 10): 30},
            valueColor: (v) => const Color(0xFFE03131),
            onTapDay: (d) => tapped = d,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('30'));
    expect(tapped, DateTime(2026, 10, 10));
  });

  testWidgets('MetricChart красит линию и точки по значению', (tester) async {
    const red = Color(0xFFE03131);
    const green = Color(0xFF2B8A3E);
    final key = GlobalKey();

    await tester.pumpWidget(
      _host(
        RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 300,
            height: 160,
            child: MetricChart(
              series: [
                (DateTime(2026, 10, 1), 10),
                (DateTime(2026, 10, 2), 90),
              ],
              labels: true,
              valueColor: (v) => v >= 50 ? green : red,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pixels = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    });

    bool near(int r, int g, int b, Color c) =>
        (r / 255 - c.r).abs() < 0.15 &&
        (g / 255 - c.g).abs() < 0.15 &&
        (b / 255 - c.b).abs() < 0.15;

    var hasRed = false;
    var hasGreen = false;
    for (var i = 0; i + 3 < pixels!.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      if (near(r, g, b, red)) hasRed = true;
      if (near(r, g, b, green)) hasGreen = true;
    }
    expect(hasRed, isTrue, reason: 'есть красные пиксели (значение < 50)');
    expect(hasGreen, isTrue, reason: 'есть зелёные пиксели (значение >= 50)');
  });
}

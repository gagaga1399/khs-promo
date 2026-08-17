import 'package:flutter/material.dart';

/// Горизонтальные столбики «выполнено / осталось» по приоритетам.
class PriorityBarChart extends StatelessWidget {
  /// Для каждого приоритета: цвет, подпись и пара (выполнено, осталось).
  final List<({
    Color color,
    String label,
    int done,
    int remaining,
  })>
  items;
  final double barHeight;

  const PriorityBarChart({super.key, required this.items, this.barHeight = 22});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (final item in items) ...[
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 56,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: barHeight,
                    child: Row(
                      children: [
                        if (item.done > 0)
                          Expanded(
                            flex: item.done,
                            child: ColoredBox(
                              color: item.color,
                              child: Center(
                                child: Text(
                                  '${item.done}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (item.remaining > 0)
                          Expanded(
                            flex: item.remaining,
                            child: ColoredBox(
                              color: scheme.surfaceContainerHigh,
                              child: Center(
                                child: Text(
                                  '${item.remaining}',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: Text(
                  item.done + item.remaining == 0
                      ? '—'
                      : '${(item.done * 100 / (item.done + item.remaining)).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Линейный график выполненных задач по дням.
class DailyLineChart extends StatelessWidget {
  /// Значения по дням (слева направо).
  final List<int> values;
  final List<String> labels;
  final Color color;

  const DailyLineChart({
    super.key,
    required this.values,
    required this.labels,
    this.color = Colors.blueAccent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (values.isEmpty) return const SizedBox.shrink();
    final maxValue =
        (values.fold<int>(0, (m, v) => v > m ? v : m)).clamp(1, 1 << 30);

    return SizedBox(
      height: 120,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LineChartPainter(
          values: values,
          labels: labels,
          gridColor: scheme.outlineVariant,
          lineColor: color,
          fillColor: color.withValues(alpha: 0.12),
          textColor: scheme.onSurfaceVariant,
          maxValue: maxValue,
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<int> values;
  final List<String> labels;
  final Color gridColor;
  final Color lineColor;
  final Color fillColor;
  final Color textColor;
  final int maxValue;

  _LineChartPainter({
    required this.values,
    required this.labels,
    required this.gridColor,
    required this.lineColor,
    required this.fillColor,
    required this.textColor,
    required this.maxValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padLeft = 24.0;
    const padBottom = 18.0;
    const padTop = 8.0;
    final chartWidth = size.width - padLeft - 4;
    final chartHeight = size.height - padTop - padBottom;

    // Горизонтальные сетки и подписи значений (0, max/2, max).
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: textColor, fontSize: 9);
    for (final f in [0.0, 0.5, 1.0]) {
      final y = padTop + chartHeight * (1 - f);
      canvas.drawLine(Offset(padLeft, y), Offset(size.width - 4, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${(maxValue * f).round()}', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    if (values.length < 2) return;

    final stepX = chartWidth / (values.length - 1);
    Offset point(int i) => Offset(
      padLeft + stepX * i,
      padTop +
          chartHeight *
              (1 - values[i].clamp(0, maxValue) / maxValue),
    );

    // Заливка под линией.
    final areaPath = Path()
      ..moveTo(point(0).dx, padTop + chartHeight)
      ..lineTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      areaPath.lineTo(point(i).dx, point(i).dy);
    }
    areaPath
      ..lineTo(point(values.length - 1).dx, padTop + chartHeight)
      ..close();
    canvas.drawPath(areaPath, Paint()..color = fillColor);

    // Линия.
    final linePath = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      linePath.lineTo(point(i).dx, point(i).dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Точки и подписи дней.
    final dotPaint = Paint()..color = lineColor;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(i), 3, dotPaint);
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(point(i).dx - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.lineColor != lineColor ||
      old.maxValue != maxValue;
}

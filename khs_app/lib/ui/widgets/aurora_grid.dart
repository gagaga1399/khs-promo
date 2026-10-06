import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Живой декор вокруг сетки календаря.
///
/// Принципиально не кольцо, как в [ShimmerRing]: тут свет живёт **внутри**
/// панели. Под содержимым медленно плывёт полярное сияние, по сетке изредка
/// пробегает блик, а по верхней кромке дышит светлая полоса с уголками по
/// краям — получается рамка, которая держит форму и на светлом, и на тёмном.
///
/// Один контроллер на весь декор: сетка перерисовывается каждый кадр, но
/// содержимое не перестраивается — [child] передаётся дальше как есть.
class AuroraGrid extends StatefulWidget {
  const AuroraGrid({
    super.key,
    required this.child,
    required this.accent,
    this.radius = 18,
    this.period = const Duration(seconds: 12),
  });

  final Widget child;

  /// Цвет сияния: обычно акцент темы.
  final Color accent;

  final double radius;

  final Duration period;

  @override
  State<AuroraGrid> createState() => _AuroraGridState();
}

class _AuroraGridState extends State<AuroraGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: AuroraBackPainter(t: _c.value, accent: widget.accent),
            ),
          ),
          ?child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: AuroraFrontPainter(t: _c.value, radius: widget.radius),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Полярное сияние под сеткой. Три пятна разных оттенков и размеров плывут по
/// разным частотам, поэтому картинка не читается как повторяющийся узор.
///
/// Сияние рисуется акцентным и белым, а не «белым по белому»: палитры проекта
/// средние тона (#E6E4DA и #424242), и чисто белый на светлой панели был бы
/// почти не виден.
class AuroraBackPainter extends CustomPainter {
  const AuroraBackPainter({required this.t, required this.accent});

  /// Фаза 0..1 за полный цикл.
  final double t;

  final Color accent;

  /// Пятно: центр плывёт по своей частоте, радиус по своей. Прозрачность
  /// задаётся в [color], а не в `paint.color` — у градиентного шейдера цвет
  /// краски на результат не влияет.
  void _blob(
    Canvas canvas,
    Size size, {
    required double fx,
    required double fy,
    required double r,
    required Color color,
  }) {
    final center = Offset(fx * size.width, fy * size.height);
    final radius = r * size.shortestSide;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: center, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * math.pi * 2;
    _blob(
      canvas,
      size,
      fx: 0.16 + 0.14 * math.sin(a),
      fy: 0.08 + 0.12 * math.sin(a * 1.3 + 1.2),
      r: 0.62,
      color: accent.withValues(alpha: 0.26),
    );
    _blob(
      canvas,
      size,
      fx: 0.86 + 0.12 * math.cos(a * 0.9 + 0.6),
      fy: 0.92 + 0.10 * math.sin(a * 1.1),
      r: 0.50,
      color: Colors.white.withValues(alpha: 0.30),
    );
    _blob(
      canvas,
      size,
      fx: 0.72 + 0.18 * math.sin(a * 0.7 + 2.1),
      fy: 0.06 + 0.08 * math.cos(a * 1.4),
      r: 0.42,
      color: accent.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(AuroraBackPainter old) =>
      old.t != t || old.accent != accent;
}

/// Блик, световая кромка и уголки поверх сетки.
class AuroraFrontPainter extends CustomPainter {
  const AuroraFrontPainter({required this.t, required this.radius});

  final double t;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );

    final a = t * math.pi * 2;
    final breathe = 0.5 + 0.5 * math.sin(a);

    // Пробегающий блик: наклонная полоса, которая за цикл проходит всю
    // панель насквозь. На светлой теме заметен слабее, поэтому добавлен к
    // верхней кромке и уголкам, а не работает в одиночку.
    final x = (-0.35 + t * 1.7) * size.width;
    final bandW = size.width * 0.2;
    final sheen = Path()
      ..moveTo(x - bandW, size.height)
      ..lineTo(x, size.height)
      ..lineTo(x + bandW * 1.6, 0)
      ..lineTo(x + bandW * 0.6, 0)
      ..close();
    canvas.drawPath(
      sheen,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(x - bandW, 0, bandW * 2.6, size.height)),
    );

    // Световая кромка сверху — читается на обоих фонах и держит верх панели.
    canvas.drawRect(
      Rect.fromLTWH(0, 0.4, size.width, 1.6),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.20 + 0.35 * breathe),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 1.6)),
    );

    // Уголки: рамка, которая остаётся, когда блик ушёл.
    final arm = 14.0;
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.22 + 0.20 * breathe);
    final w = size.width;
    final h = size.height;
    canvas
      ..drawPath(
        Path()
          ..moveTo(0, arm)
          ..lineTo(0, 0)
          ..lineTo(arm, 0),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(w - arm, 0)
          ..lineTo(w, 0)
          ..lineTo(w, arm),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(0, h - arm)
          ..lineTo(0, h)
          ..lineTo(arm, h),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(w - arm, h)
          ..lineTo(w, h)
          ..lineTo(w, h - arm),
        corner,
      );
  }

  @override
  bool shouldRepaint(AuroraFrontPainter old) =>
      old.t != t || old.radius != radius;
}

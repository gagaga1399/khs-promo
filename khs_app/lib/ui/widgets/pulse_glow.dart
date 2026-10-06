import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Мягко дышащее белое свечение под содержимым.
///
/// Отдельный виджет, потому что нужен сразу в нескольких местах календаря, а
/// контроллер должен быть один: дыхание на 40 ячейках не должно заводить по
/// тикеру на каждую, поэтому передаётся общий [animation], а слушателей много.
class PulseGlow extends StatelessWidget {
  const PulseGlow({
    super.key,
    required this.animation,
    required this.child,
    this.min = 0.08,
    this.max = 0.28,
    this.blur = 7,
    this.radius,
  });

  /// Общий [Animation] на несколько виджетов: один тикер, много слушателей.
  final Animation<double> animation;

  final Widget child;

  /// Прозрачность в нижней и верхней точке дыхания.
  final double min;
  final double max;

  final double blur;

  /// null — круг по меньшей стороне, иначе скруглённый прямоугольник.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => CustomPaint(
        foregroundPainter: PulseGlowPainter(
          alpha:
              min +
              (max - min) *
                  (0.5 + 0.5 * math.sin(animation.value * math.pi * 2)),
          blur: blur,
          radius: radius,
        ),
        child: child,
      ),
    );
  }
}

/// Свечение вынесено публично, чтобы тест мог проверить, что прозрачность
/// действительно ходит, а не рисует одну и ту же картинку.
class PulseGlowPainter extends CustomPainter {
  const PulseGlowPainter({required this.alpha, this.blur = 7, this.radius});

  final double alpha;
  final double blur;
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius == null
        ? RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2))
        : RRect.fromRectAndRadius(rect, Radius.circular(radius!));
    canvas.drawRRect(
      rrect.inflate(blur * 0.35),
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  @override
  bool shouldRepaint(PulseGlowPainter old) =>
      old.alpha != alpha || old.blur != blur || old.radius != radius;
}

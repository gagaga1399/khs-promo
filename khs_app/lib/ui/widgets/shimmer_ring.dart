import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Постоянно бегущий белый перелив по контуру скруглённого прямоугольника.
///
/// Читается на любом фоне, потому что перелив здесь не заливка, а свет:
/// постоянная кайма задаёт форму даже там, где пятно в этот момент прозрачно,
/// а размытый ореол поднимает поле над фоном без контраста с текстом внутри.
///
/// Рисуется поверх потомка ([CustomPaint.foregroundPainter]), а не под ним:
/// у поля непрозрачная заливка, и ободок под ней был бы не виден.
class ShimmerRing extends StatefulWidget {
  const ShimmerRing({
    super.key,
    required this.child,
    this.radius = 16,
    this.period = const Duration(milliseconds: 2800),
  });

  final Widget child;

  /// Радиус скругления должен совпадать с радиусом рамки потомка, иначе
  /// перелив разойдётся с формой поля.
  final double radius;

  /// За сколько цикл обходит поле целиком.
  final Duration period;

  @override
  State<ShimmerRing> createState() => _ShimmerRingState();
}

class _ShimmerRingState extends State<ShimmerRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => CustomPaint(
        foregroundPainter: ShimmerRingPainter(
          angle: _controller.value * math.pi * 2,
          pulse: 0.75 + 0.25 * math.sin(_controller.value * math.pi * 2),
          radius: widget.radius,
        ),
        child: child,
      ),
    );
  }
}

/// Вынесен в отдельный публичный класс, чтобы тест мог проверить, что угол
/// действительно ходит, а не рисует одну и ту же картинку.
class ShimmerRingPainter extends CustomPainter {
  const ShimmerRingPainter({
    required this.angle,
    required this.pulse,
    required this.radius,
  });

  /// Где сейчас световое пятно, в оборотах.
  final double angle;

  /// Яркость перелива: медленное дыхание, чтобы не слепить и не погаснуть.
  final double pulse;

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const white = Color(0xFFFFFFFF);
    const width = 1.6;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(width / 2),
      Radius.circular(radius),
    );

    // Ореол: поднимает поле над любым фоном, но сам по себе слабый.
    canvas.drawRRect(
      rrect.inflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2.4
        ..color = white.withValues(alpha: 0.12 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Постоянная кайма: форму видно на любом фоне и в тот момент, когда сам
    // перелив в этой точке прозрачен.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = white.withValues(alpha: 0.16),
    );

    // Сам перелив: SweepGradient вращается вокруг центра, поэтому свет бежит
    // по контуру, а не расползается по заливке поля.
    final sweep = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      transform: GradientRotation(angle),
      colors: [
        white.withValues(alpha: 0),
        white.withValues(alpha: 0),
        white.withValues(alpha: 0.62 * pulse),
        white.withValues(alpha: 0),
        white.withValues(alpha: 0),
      ],
      stops: const [0, 0.3, 0.5, 0.7, 1],
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 1.7
        ..strokeCap = StrokeCap.round
        ..shader = sweep.createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
  }

  @override
  bool shouldRepaint(ShimmerRingPainter old) =>
      old.angle != angle || old.pulse != pulse || old.radius != radius;
}

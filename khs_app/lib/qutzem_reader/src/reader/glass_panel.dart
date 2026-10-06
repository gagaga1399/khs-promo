import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Размытие подложки. Значение такое же, как у плавающей панели навигации в
/// KHS Tasks, но продублировано намеренно: читалка собирается и
/// распространяется отдельно от KHS, тянуть в неё зависимость от `ui/`
/// нельзя.
const double kReaderGlassBlur = 26;

/// Плотность подложки. Матовый фон = полупрозрачный: книга под панелью должна
/// просвечивать размытыми пятнами, поэтому глухой заливки здесь быть не
/// должно.
const double kReaderGlassAlpha = 0.64;

/// Матовая полупрозрачная панель для нижних панелей читалки.
///
/// Размывает то, что находится под панелью (BackdropFilter), поверх кладётся
/// подложка с альфой и мягкая тень. Скруглённая панель повторяет навигацию
/// (тонкая рамка по всему контуру), панель вплотную к краю экрана получает
/// только линию сверху — иначе рамка упирается в края экрана.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 0,
    this.tint,
    this.blur = kReaderGlassBlur,
    this.topBorder = true,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Скругление углов; 0 — панель вплотную к краю экрана.
  final double radius;

  /// Оттенок подложки. null — берётся из темы.
  final Color? tint;
  final double blur;
  final bool topBorder;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base =
        tint ??
        (dark
            ? theme.colorScheme.surface
            : theme.colorScheme.surface.withValues(alpha: 0.9));
    final line = (dark ? Colors.white : Colors.black).withValues(alpha: 0.10);

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: base.withValues(alpha: kReaderGlassAlpha),
            border: radius > 0
                ? Border.all(color: line)
                : topBorder
                ? Border(top: BorderSide(color: line))
                : null,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (!shadow) return panel;

    // Тень держим на внешнем слое: ClipRRect и BackdropFilter обрезают всё
    // внутри себя, поэтому тень на внутреннем виджете срезалась бы целиком.
    // У панели вплотную к краю тень идёт вверх — так она читается как слой
    // над текстом, а не как тень, обрезанная краем экрана.
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.50 : 0.18),
            blurRadius: 28,
            offset: Offset(0, radius > 0 ? 10 : -3),
          ),
        ],
      ),
      child: panel,
    );
  }
}

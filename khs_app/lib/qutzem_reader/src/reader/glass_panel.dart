import 'dart:ui';

import 'package:flutter/material.dart';

/// Матовое «стекло» для нижних панелей читалки и QutZem Reader.
///
/// Размывает то, что находится под панелью (BackdropFilter), поэтому текст
/// книги просвечивает и растворяется — как в Spotify. Поверх размытия
/// кладётся полупрозрачная заливка [tint], тонкая линия сверху и мягкая
/// тень, чтобы панель не «слипалась» с текстом.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 0,
    this.tint,
    this.blur = 20,
    this.topBorder = true,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Скругление углов; 0 — панель вплотную к краю экрана.
  final double radius;

  /// Цвет заливки поверх размытия. null — берётся из темы.
  final Color? tint;
  final double blur;
  final bool topBorder;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = tint ??
        (dark
            ? theme.colorScheme.surface
            : theme.colorScheme.surface.withValues(alpha: 0.9));
    final line = (dark ? Colors.white : Colors.black).withValues(alpha: 0.10);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: base.withValues(alpha: dark ? 0.55 : 0.62),
            border: topBorder ? Border(top: BorderSide(color: line)) : null,
            boxShadow: shadow
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, -3),
                    )
                  ]
                : null,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

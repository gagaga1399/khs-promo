import 'package:flutter/material.dart';

/// Показывает диалог выбора акцентного цвета темы (HSV-палитра,
/// цвет можно выбрать любой). Возвращает выбранный [Color] или null.
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  required Color initial,
  required String title,
  required String cancelLabel,
  required String okLabel,
}) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(
      initial: initial,
      title: title,
      cancelLabel: cancelLabel,
      okLabel: okLabel,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final String title;
  final String cancelLabel;
  final String okLabel;

  const _ColorPickerDialog({
    required this.initial,
    required this.title,
    required this.cancelLabel,
    required this.okLabel,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  String get _hex {
    final rgb = _hsv.toColor();
    final value = rgb.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _update(double? hue, double? sat, double? val) {
    setState(() {
      _hsv = HSVColor.fromAHSV(
        1,
        hue ?? _hsv.hue,
        sat ?? _hsv.saturation,
        val ?? _hsv.value,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SvBox(
            hue: _hsv.hue,
            color: _hsv.toColor(),
            onChanged: (s, v) => _update(null, s, v),
          ),
          const SizedBox(height: 12),
          _HueBar(hue: _hsv.hue, onChanged: (h) => _update(h, null, null)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _hsv.toColor(),
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
              ),
              const SizedBox(width: 12),
              Text(_hex, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hsv.toColor()),
          child: Text(widget.okLabel),
        ),
      ],
    );
  }
}

/// Квадрат насыщенность×яркость (x — saturation, y — value).
class _SvBox extends StatelessWidget {
  final double hue;
  final Color color;
  final void Function(double saturation, double value) onChanged;

  const _SvBox({
    required this.hue,
    required this.color,
    required this.onChanged,
  });

  static const double _height = 160;
  static const double _radius = 9;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanDown: (d) => _pick(d.localPosition, width),
          onPanUpdate: (d) => _pick(d.localPosition, width),
          child: CustomPaint(
            size: Size(width, _height),
            painter: _SvPainter(
              hue: hue,
              pointer: _pointer(hsv, width),
            ),
          ),
        );
      },
    );
  }

  /// Центр курсора: он ходит по всей области, но круг не вылезает за края,
  /// потому что центр ограничен радиусом.
  Offset _pointer(HSVColor hsv, double width) {
    return Offset(
      _radius + hsv.saturation * (width - 2 * _radius),
      _radius + (1 - hsv.value) * (_height - 2 * _radius),
    );
  }

  void _pick(Offset pos, double width) {
    final sat =
        ((pos.dx.clamp(_radius, width - _radius) - _radius) /
                (width - 2 * _radius))
            .clamp(0.0, 1.0);
    final val =
        (1 -
                ((pos.dy.clamp(_radius, _height - _radius) - _radius) /
                    (_height - 2 * _radius)))
            .clamp(0.0, 1.0);
    onChanged(sat, val);
  }
}

class _SvPainter extends CustomPainter {
  final double hue;
  final Offset pointer;

  _SvPainter({required this.hue, required this.pointer});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base, Colors.black],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );

    canvas.drawCircle(
      pointer,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(pointer, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SvPainter old) =>
      old.hue != hue || old.pointer != pointer;
}

/// Полоса выбора оттенка (0..360).
class _HueBar extends StatelessWidget {
  final double hue;
  final void Function(double hue) onChanged;

  const _HueBar({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const colors = <Color>[
      Color(0xFFFF0000),
      Color(0xFFFFFF00),
      Color(0xFF00FF00),
      Color(0xFF00FFFF),
      Color(0xFF0000FF),
      Color(0xFFFF00FF),
      Color(0xFFFF0000),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanDown: (d) => _pick(d.localPosition.dx, width),
          onPanUpdate: (d) => _pick(d.localPosition.dx, width),
          child: SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: colors),
                    ),
                  ),
                ),
                Positioned(
                  left: hue / 360 * (width - 12),
                  child: Container(
                    width: 12,
                    height: 24,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _pick(double dx, double width) {
    final x = dx.clamp(6.0, width - 6.0);
    onChanged(((x - 6) / (width - 12) * 360).clamp(0, 360));
  }
}

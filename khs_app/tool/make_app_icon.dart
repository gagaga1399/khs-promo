// Рисует фирменную иконку приложения KHS в тематике статистики: градиент
// фиолетовый → циан и белые столбцы диаграммы (последний — зелёный, «цель
// достигнута»). Пишет все Android mipmap-размеры и Windows app_icon.ico.
// Запуск (из khs_app): dart run tool/make_app_icon.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main() {
  const base = 1024;
  final icon = _draw(base);

  final android = <(String, int)>[
    ('android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48),
    ('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72),
    ('android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96),
    ('android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144),
    ('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192),
  ];
  for (final (path, size) in android) {
    final scaled = img.copyResize(
      icon,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    final file = File(path);
    file.writeAsBytesSync(img.encodePng(scaled));
    stdout.writeln('written ${file.path} (${file.lengthSync()} bytes)');
  }

  final ico = File('windows/runner/resources/app_icon.ico');
  ico.writeAsBytesSync(_encodeIco(icon));
  stdout.writeln('written ${ico.path} (${ico.lengthSync()} bytes)');
}

/// Разовый рендер иконки в заданном размере.
img.Image _draw(int size) {
  final image = img.Image(size, size);
  final n = size.toDouble();

  const violet = (141, 82, 238); // #8D52EE
  const cyan = (22, 189, 202); // #16BDCA
  const green = (52, 211, 153, 255); // #34D399

  // 1. Фон: градиент по вертикали фиолетовый → циан.
  for (var y = 0; y < size; y++) {
    final t = y / n;
    final r = (violet.$1 + (cyan.$1 - violet.$1) * t).round();
    final g = (violet.$2 + (cyan.$2 - violet.$2) * t).round();
    final b = (violet.$3 + (cyan.$3 - violet.$3) * t).round();
    _fillRect(image, 0, y, size, 1, (r, g, b, 255));
  }

  // 2. Мягкие световые пятна.
  _fillCircleA(
    image,
    (n * 0.83).round(),
    (n * 0.12).round(),
    (n * 0.30).round(),
    (255, 255, 255, 26),
  );
  _fillCircleA(
    image,
    (n * 0.10).round(),
    (n * 0.88).round(),
    (n * 0.22).round(),
    (255, 255, 255, 18),
  );

  // 3. Столбцы диаграммы. Нижний край с лёгким ступенчатым подъёмом.
  final shifts = [-0.30, -0.18, -0.02, 0.14, 0.32]; // дно каждого бара
  final barW = n * 0.135;
  final gap = n * 0.025;
  final baseline = n * 0.82;
  final totalW = shifts.length * barW + (shifts.length - 1) * gap;
  var x = (n - totalW) / 2;
  final heights = [0.28, 0.42, 0.56, 0.68, 0.82];

  for (var i = 0; i < shifts.length; i++) {
    final bottom = baseline + shifts[i] * n * 0.16;
    final top = bottom - n * heights[i];
    final color = i == shifts.length - 1 ? green : (255, 255, 255, 235);
    _roundedRect(image, x, top, barW, bottom - top, n * 0.052, color);
    // Светлый контур поверх самого высокого бара — «успех».
    if (i == shifts.length - 1) {
      _roundedRect(
        image,
        x - n * 0.012,
        top - n * 0.02,
        barW + n * 0.024,
        bottom - top + n * 0.024,
        n * 0.058,
        (255, 255, 255, 70),
      );
    }
    x += barW + gap;
  }

  // 4. Тонкий вертикальный росчерк-сверка слева сверху.
  final streakX = (n * 0.20).round();
  for (var y = (n * 0.24).round(); y < (n * 0.36).round(); y++) {
    _fillRect(image, streakX, y, (n * 0.05).round(), 1, (255, 255, 255, 100));
  }

  return image;
}

void _fillRect(
  img.Image image,
  int x,
  int y,
  int w,
  int h,
  (int, int, int, int) c,
) {
  img.fillRect(
    image,
    x,
    y,
    x + w,
    y + h,
    img.getColor(c.$1, c.$2, c.$3, c.$4),
  );
}

void _fillCircleA(
  img.Image image,
  int cx,
  int cy,
  int radius,
  (int, int, int, int) c,
) {
  img.fillCircle(
    image,
    cx,
    cy,
    radius,
    img.getColor(c.$1, c.$2, c.$3, c.$4),
  );
}

/// Прямоугольник со скруглёнными углами (по углам — круги).
void _roundedRect(
  img.Image image,
  double x,
  double y,
  double w,
  double h,
  double radius,
  (int, int, int, int) c,
) {
  final r = math.min(radius, math.min(w, h) / 2).round().clamp(1, 1 << 30);
  final color = img.getColor(c.$1, c.$2, c.$3, c.$4);
  final xi = x.round();
  final yi = y.round();
  final x2 = (x + w).round();
  final y2 = (y + h).round();
  img.fillRect(image, xi, yi + r, x2, y2 - r, color);
  img.fillRect(image, xi + r, yi, x2 - r, y2, color);
  img.fillCircle(image, xi + r, yi + r, r, color);
  img.fillCircle(image, x2 - r, yi + r, r, color);
  img.fillCircle(image, xi + r, y2 - r, r, color);
  img.fillCircle(image, x2 - r, y2 - r, r, color);
}

Uint8List _encodeIco(img.Image source) {
  const sizes = <int>[16, 24, 32, 48, 64, 128, 256];
  final pngs = <int, List<int>>{
    for (final s in sizes)
      s: img.encodePng(img.copyResize(source, width: s, height: s)),
  };

  final entries = pngs.entries.toList();
  final header = BytesBuilder();
  header.add(_u16(0)); // reserved
  header.add(_u16(1)); // type: icon
  header.add(_u16(entries.length));

  final body = BytesBuilder();
  var offset = 6 + 16 * entries.length;
  for (final entry in entries) {
    final dim = entry.key >= 256 ? 0 : entry.key;
    header.addByte(dim); // width
    header.addByte(dim); // height
    header.addByte(0); // palette
    header.addByte(0); // reserved
    header.add(_u16(1)); // color planes
    header.add(_u16(32)); // bits per pixel
    header.add(_u32(entry.value.length));
    header.add(_u32(offset));
    body.add(entry.value);
    offset += entry.value.length;
  }

  return (BytesBuilder()
        ..add(header.toBytes())
        ..add(body.toBytes()))
      .toBytes();
}

Uint8List _u16(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
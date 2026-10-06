import 'package:flutter/material.dart';

/// Порция прогресса скачивания.
class DownloadSample {
  const DownloadSample(this.received, this.total, this.bytesPerSecond);

  const DownloadSample.zero() : received = 0, total = 0, bytesPerSecond = 0;

  /// Сколько байт пришло.
  final int received;

  /// Сколько байт ожидается. 0, если сервер не сообщил длину.
  final int total;

  /// Усреднённая скорость, байт в секунду.
  final double bytesPerSecond;

  /// Доля загрузки. null, пока длина неизвестна: индикатор в этом случае
  /// бесконечный, а не застывший на нуле.
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

/// Следит за скачиванием и отдаёт его в диалог.
///
/// Скорость усредняется: мгновенная на одном куске скачет слишком сильно и
/// на экране выглядит как сбой. Обновление не чаще раза в четверть секунды,
/// иначе на медленной сети диалог сам станет тормозом.
class DownloadProgress {
  final ValueNotifier<DownloadSample> value = ValueNotifier(
    const DownloadSample.zero(),
  );

  final Stopwatch _clock = Stopwatch()..start();

  int _lastBytes = 0;
  Duration _lastAt = Duration.zero;
  double _speed = 0;

  /// Обработчик для `onProgress` у [UpdateChecker.download].
  void call(int received, int total) {
    final now = _clock.elapsed;
    final dt = (now - _lastAt).inMilliseconds / 1000.0;
    if (dt >= 0.25) {
      final instant = (received - _lastBytes) / dt;
      _speed = _speed == 0 ? instant : _speed * 0.7 + instant * 0.3;
      _lastBytes = received;
      _lastAt = now;
    }
    value.value = DownloadSample(received, total, _speed);
  }

  void dispose() {
    _clock.stop();
    value.dispose();
  }
}

/// Формат размера файла: «12,3 МБ».
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  return '$bytes Б';
}

/// Диалог загрузки: сколько скачано, сколько всего, процент и скорость.
///
/// Раньше в хабе стоял круговой индикатор без цифр: на файле в 80 МБ он
/// выглядел одинаково и минуту, и три, и казалось, что загрузка встала.
class DownloadProgressDialog extends StatelessWidget {
  const DownloadProgressDialog({
    super.key,
    required this.fileName,
    required this.progress,
    required this.title,
  });

  /// Имя файла, чтобы было видно, что именно качается.
  final String fileName;

  final DownloadProgress progress;

  /// Заголовок, обычно из строк локализации.
  final String title;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DownloadSample>(
      valueListenable: progress.value,
      builder: (context, s, _) {
        final scheme = Theme.of(context).colorScheme;
        final percent = s.fraction == null ? null : (s.fraction! * 100).round();
        final size = s.total > 0
            ? '${formatBytes(s.received)} из ${formatBytes(s.total)}'
            : formatBytes(s.received);
        final speed = s.bytesPerSecond > 0
            ? ' · ${formatBytes(s.bytesPerSecond.round())}/с'
            : '';
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              LinearProgressIndicator(
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                value: s.fraction,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '$size$speed',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    percent == null ? '…' : '$percent%',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

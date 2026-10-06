import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:khs/qutzem_reader/src/ai.dart';

void main() {
  group('prepareImageForAi', () {
    test('уменьшает большую картинку до 1600px по длинной стороне', () {
      final big = img.Image(4000, 2000);
      img.fill(big, img.getColor(255, 255, 255));
      final source = Uint8List.fromList(img.encodePng(big));

      final out = prepareImageForAi(source);
      final decoded = img.decodeImage(out)!;

      expect(decoded.width, lessThanOrEqualTo(1600));
      expect(decoded.height, lessThanOrEqualTo(1600));
      // Пропорции сохранены: 4000x2000 -> вдвое меньше по высоте.
      expect(decoded.width / decoded.height, closeTo(2.0, 0.05));
    });

    test('портретную картинку уменьшает по высоте', () {
      final big = img.Image(1200, 3600);
      img.fill(big, img.getColor(10, 10, 10));
      final source = Uint8List.fromList(img.encodePng(big));

      final decoded = img.decodeImage(prepareImageForAi(source))!;

      expect(decoded.height, lessThanOrEqualTo(1600));
      expect(decoded.width / decoded.height, closeTo(1 / 3, 0.05));
    });

    test('не трогает небольшую картинку', () {
      final small = img.Image(400, 300);
      img.fill(small, img.getColor(128, 128, 128));
      final source = Uint8List.fromList(img.encodePng(small));

      final decoded = img.decodeImage(prepareImageForAi(source))!;

      expect(decoded.width, 400);
      expect(decoded.height, 300);
    });

    test('на выходе именно JPEG, а не исходный PNG', () {
      final big = img.Image(2000, 2000);
      img.fill(big, img.getColor(200, 30, 30));
      final source = Uint8List.fromList(img.encodePng(big));

      final out = prepareImageForAi(source);

      // JPEG начинается с маркера SOI (FF D8) и закрывается EOI (FF D9).
      expect(out.length, greaterThan(3));
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      expect(out[out.length - 2], 0xFF);
      expect(out[out.length - 1], 0xD9);
    });

    test('нечитаемые байты возвращаются как есть, без исключения', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      expect(prepareImageForAi(garbage), garbage);
    });
  });

  group('зрение провайдеров', () {
    test('картинки принимают только провайдеры с ключом', () {
      expect(AiProvider.gemini.supportsVision, isTrue);
      expect(AiProvider.openrouter.supportsVision, isTrue);
      expect(AiProvider.groq.supportsVision, isTrue);
    });

    test('Ollama и бесплатный провайдер картинки не принимают', () {
      expect(AiProvider.ollama.supportsVision, isFalse);
      expect(AiProvider.free.supportsVision, isFalse);
      expect(AiProvider.ollama.visionModelHint, isEmpty);
      expect(AiProvider.free.visionModelHint, isEmpty);
    });

    test('у зрячих провайдеров есть подсказка с моделью', () {
      expect(AiProvider.gemini.visionModelHint, isNotEmpty);
      expect(AiProvider.openrouter.visionModelHint, isNotEmpty);
      expect(AiProvider.groq.visionModelHint, isNotEmpty);
    });
  });
}

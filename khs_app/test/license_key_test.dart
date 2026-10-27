import 'package:flutter_test/flutter_test.dart';
import 'package:khs/services/license_key.dart';

void main() {
  group('LicenseKey', () {
    test('принимает верный ключ', () {
      expect(LicenseKey.isValid(LicenseKey.valid), true);
    });

    test('нормализует регистр, пробелы и дефисы', () {
      final lower = LicenseKey.valid.toLowerCase();
      expect(LicenseKey.isValid(lower), true);
      expect(LicenseKey.isValid('  ${lower.replaceAll('-', ' ')} '), true);
      expect(LicenseKey.isValid(LicenseKey.valid.replaceAll('-', '')), true);
    });

    test('отклоняет пустой и неверный ключ', () {
      expect(LicenseKey.isValid(''), false);
      expect(LicenseKey.isValid('   '), false);
      expect(LicenseKey.isValid('KHS-0000-0000-0000'), false);
      expect(LicenseKey.isValid('abc'), false);
    });
  });
}

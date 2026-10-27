import 'package:flutter_test/flutter_test.dart';
import 'package:khs/services/daily_quote.dart';

void main() {
  test('ru и en наборы непусты и одинаковой длины', () {
    expect(DailyQuotes.ru, isNotEmpty);
    expect(DailyQuotes.en, isNotEmpty);
    expect(DailyQuotes.ru.length, DailyQuotes.en.length);
  });

  test('цитата дня стабильна в пределах дня', () {
    final morning = DailyQuotes.forDay(DateTime(2026, 3, 14, 7), russian: true);
    final evening = DailyQuotes.forDay(
      DateTime(2026, 3, 14, 23, 59),
      russian: true,
    );
    expect(morning.text, evening.text);
    expect(morning.author, evening.author);
  });

  test('на следующий день цитата меняется', () {
    final a = DailyQuotes.forDay(DateTime(2026, 3, 14), russian: true);
    final b = DailyQuotes.forDay(DateTime(2026, 3, 15), russian: true);
    expect(a.text, isNot(b.text));
  });

  test('индекс корректен для любых дат, включая прошлое', () {
    for (var i = 0; i < 4000; i++) {
      final day = DateTime(2000, 1, 1).add(Duration(days: i - 2000));
      for (final russian in [true, false]) {
        final q = DailyQuotes.forDay(day, russian: russian);
        expect(q.text, isNotEmpty);
        expect(q.author, isNotEmpty);
      }
    }
  });
}

/// Цитата дня. Полностью офлайн: тексты вшиты в бинарник, никакой сети.
/// Цитата детерминирована по календарной дате, поэтому весь день держится
/// одна и та же, а на следующий день сменяется.
library;

class DailyQuote {
  const DailyQuote(this.text, this.author);

  final String text;
  final String author;
}

/// Наборы цитат по языкам. Индекс один и тот же для обоих языков, поэтому
/// цитата дня «совпадает» при переключении локали (доступна и в en, и в ru).
abstract final class DailyQuotes {
  static const List<DailyQuote> ru = [
    DailyQuote('Дорогу осилит идущий.', 'Латинская пословица'),
    DailyQuote(
      'Не откладывай на завтра то, что можно сделать сегодня.',
      'Бенджамин Франклин',
    ),
    DailyQuote('Капля камень точит не силой, а частым падением.', 'Овидий'),
    DailyQuote('Терпение и труд всё перетрут.', 'Русская пословица'),
    DailyQuote('Дисциплина — это мост между целью и результатом.', 'Джим Рон'),
    DailyQuote(
      'Маленькие шаги каждый день важнее большого рывка раз в год.',
      'Народная мудрость',
    ),
    DailyQuote(
      'Сначала делай то, что необходимо, потом — что возможно.',
      'Фрэнсис Бэкон',
    ),
    DailyQuote('Тише едешь — дальше будешь.', 'Русская пословица'),
    DailyQuote('Мы то, что мы делаем постоянно.', 'Аристотель'),
    DailyQuote(
      'Кто хочет — ищет возможности, кто не хочет — ищет причины.',
      'Сократ',
    ),
    DailyQuote('Только тот живёт, кто служит великой цели.', 'Сенека'),
    DailyQuote(
      'Лучшее время посадить дерево было двадцать лет назад. Следующее лучшее — сегодня.',
      'Китайская пословица',
    ),
    DailyQuote('Начатое дело наполовину сделано.', 'Гораций'),
    DailyQuote(
      'Не сравнивай себя с другими — сравнивай себя вчерашнего с собой сегодняшним.',
      'Джордан Питерсон',
    ),
    DailyQuote('Спокойный ум даёт силу.', 'Народная мудрость'),
    DailyQuote('Сделай шаг — и дорога появится сама.', 'Народная мудрость'),
    DailyQuote(
      'Корни растут в тишине, а плоды — на виду.',
      'Народная мудрость',
    ),
    DailyQuote(
      'Успех — это сумма малых усилий, повторяемых день за днём.',
      'Роберт Кольер',
    ),
    DailyQuote(
      'Воля — это то, что заставляет встать, когда не хочется.',
      'Народная мудрость',
    ),
    DailyQuote(
      'Не бойся медленно идти, бойся стоять на месте.',
      'Китайская пословица',
    ),
    DailyQuote(
      'Учись у прошлого, живи настоящим, верь в будущее.',
      'Народная мудрость',
    ),
    DailyQuote('Своё дело не тяготит, а растит.', 'Народная мудрость'),
    DailyQuote('Кто рано встаёт, тому Бог даёт.', 'Русская пословица'),
    DailyQuote(
      'Будь тем изменением, которое хочешь видеть в мире.',
      'Махатма Ганди',
    ),
    DailyQuote('Дорога в тысячу миль начинается с одного шага.', 'Лао-цзы'),
    DailyQuote(
      'Собирай день по крохам — и вырастет дерево.',
      'Народная мудрость',
    ),
  ];

  static const List<DailyQuote> en = [
    DailyQuote('The journey is the reward.', 'Chinese proverb'),
    DailyQuote(
      'Never put off till tomorrow what you can do today.',
      'Benjamin Franklin',
    ),
    DailyQuote(
      'Dripping water hollows out stone, not through force but through persistence.',
      'Ovid',
    ),
    DailyQuote(
      'Patience and effort will grind through anything.',
      'Russian proverb',
    ),
    DailyQuote(
      'Discipline is the bridge between goals and accomplishment.',
      'Jim Rohn',
    ),
    DailyQuote(
      'Small steps every day beat one great leap a year.',
      'Folk wisdom',
    ),
    DailyQuote(
      'First do what is necessary, then what is possible.',
      'Francis Bacon',
    ),
    DailyQuote('Make haste slowly.', 'Latin proverb'),
    DailyQuote('We are what we repeatedly do.', 'Aristotle'),
    DailyQuote(
      'He who wants finds a way; he who does not finds an excuse.',
      'Socrates',
    ),
    DailyQuote(
      'Let the one who does good for great deeds be the one who lives.',
      'Seneca',
    ),
    DailyQuote(
      'The best time to plant a tree was 20 years ago. The next best is today.',
      'Chinese proverb',
    ),
    DailyQuote('Well begun is half done.', 'Horace'),
    DailyQuote(
      'Compare yourself to who you were yesterday, not to who someone else is today.',
      'Jordan Peterson',
    ),
    DailyQuote('A calm mind brings inner strength.', 'Folk wisdom'),
    DailyQuote('Take a step, and the road appears.', 'Folk wisdom'),
    DailyQuote(
      'Roots grow in silence, fruit ripens in the light.',
      'Folk wisdom',
    ),
    DailyQuote(
      'Success is the sum of small efforts repeated day after day.',
      'Robert Collier',
    ),
    DailyQuote(
      'Willpower is what makes you stand up when you do not want to.',
      'Folk wisdom',
    ),
    DailyQuote(
      'Be not afraid of going slowly, be afraid only of standing still.',
      'Chinese proverb',
    ),
    DailyQuote(
      'Learn from the past, live in the present, believe in the future.',
      'Folk wisdom',
    ),
    DailyQuote(
      'Work you love does not weigh you down, it lifts you up.',
      'Folk wisdom',
    ),
    DailyQuote('The early bird catches the worm.', 'English proverb'),
    DailyQuote('Be the change you wish to see in the world.', 'Mahatma Gandhi'),
    DailyQuote(
      'A journey of a thousand miles begins with a single step.',
      'Laozi',
    ),
    DailyQuote(
      'Gather each day little by little, and a tree will grow.',
      'Folk wisdom',
    ),
  ];

  /// Цитата для календарного дня [day]. Без сети: только смещение от опорной
  /// даты по модулю длины списка.
  static DailyQuote forDay(DateTime day, {required bool russian}) {
    final list = russian ? ru : en;
    final date = DateTime(day.year, day.month, day.day);
    final offset = date.difference(DateTime(2020, 1, 1)).inDays;
    final index = ((offset % list.length) + list.length) % list.length;
    return list[index];
  }
}

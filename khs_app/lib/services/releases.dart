/// Тип изменения в релизе.
enum ChangeType { feature, bugfix, improvement }

/// Одно изменение в релизе с типом.
class ChangeEntry {
  final String text;
  final ChangeType type;

  const ChangeEntry(this.text, [this.type = ChangeType.improvement]);
}

/// Версия релиза и что в ней изменилось.
class ReleaseInfo {
  final String version;
  final String date;
  final List<ChangeEntry> changes;

  const ReleaseInfo({
    required this.version,
    required this.date,
    required this.changes,
  });
}

const List<ReleaseInfo> khsReleases = [
  ReleaseInfo(
    version: '1.2.22',
    date: '13.09.2026',
    changes: [
      ChangeEntry('Загрузка обновления: окно с процентом и прогресс-баром', ChangeType.feature),
      ChangeEntry('Загрузку больше не обрывает между чанками файла', ChangeType.bugfix),
      ChangeEntry('Редактор заметок: панель форматирования как в Obsidian — жирный, курсив, код, заголовки, списки, цитаты', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.21',
    date: '13.09.2026',
    changes: [
      ChangeEntry('Проверка обновлений: понятно, когда ПК недоступен, а когда на ПК не настроен файл обновления', ChangeType.improvement),
      ChangeEntry('Обновление по Wi-Fi снова находит файлы рядом с запущенным KHS', ChangeType.bugfix),
    ],
  ),
  ReleaseInfo(
    version: '1.2.20',
    date: '13.09.2026',
    changes: [
      ChangeEntry('Поиск по всем задачам и заметкам', ChangeType.feature),
      ChangeEntry('Удаление выполненных и просроченных задач одним действием', ChangeType.feature),
      ChangeEntry('Бэкап в файл: экспорт и импорт задач и заметок', ChangeType.feature),
      ChangeEntry('Запуск KHS вместе со стартом Windows', ChangeType.feature),
      ChangeEntry('Если «в 9 часов» уже прошло — спрашиваем: 9:00 или 21:00', ChangeType.improvement),
      ChangeEntry('Время без даты теперь всегда ставится на сегодня', ChangeType.bugfix),
      ChangeEntry('Плавные переходы между экранами и анимация галочек задач', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.2.19',
    date: '12.09.2026',
    changes: [
      ChangeEntry('«Что нового» раскрывается по версиям как папки — жми на свою', ChangeType.improvement),
      ChangeEntry('Защита от повтора перехваченных запросов синка', ChangeType.improvement),
      ChangeEntry('Ключ доступа автоматически меняется (ротация) — старый действует ещё 3 дня', ChangeType.improvement),
      ChangeEntry('Телефон привязывается к своему ПК — чужой сервер данные не примет', ChangeType.improvement),
      ChangeEntry('Слияние не доверяет «будущим» временам накрученных часов', ChangeType.improvement),
      ChangeEntry('Защита сервера от перегрузки запросами', ChangeType.improvement),
      ChangeEntry('Раздача файлов обновлений только по белому списку имён', ChangeType.improvement),
      ChangeEntry('Проверка соединения доступна только обладателю ключа', ChangeType.improvement),
      ChangeEntry('Obsidian: удаляются только заметки KHS, чужие файлы не трогаются', ChangeType.improvement),
      ChangeEntry('Сетевой конфиг Android формализован, убрано лишнее разрешение', ChangeType.improvement),
      ChangeEntry('Обновления проверяются по цифровой подписи — подменить файлы по Wi-Fi нельзя', ChangeType.improvement),
      ChangeEntry('Синхронизация шифруется: данные и ключ доступа не передаются открытым текстом', ChangeType.improvement),
      ChangeEntry('Сервер можно ограничить одним IP, чтобы его не видели чужие устройства', ChangeType.improvement),
      ChangeEntry('Блокировка перебора ключа доступа', ChangeType.improvement),
      ChangeEntry('Бэкап на Android отключён — данные не уезжают в облако Google', ChangeType.improvement),
      ChangeEntry('Исправлено появление лишних копий ежедневных задач', ChangeType.bugfix),
      ChangeEntry('Синхронизация защищена: без ключа или с неверным ключом доступ закрыт', ChangeType.improvement),
      ChangeEntry('Пустой ключ доступа создаётся автоматически на ПК', ChangeType.improvement),
      ChangeEntry('Ключ больше не светится в сетевом адресе и журнале', ChangeType.bugfix),
      ChangeEntry('В настройках — кнопка «показать/скрыть» ключ доступа', ChangeType.feature),
      ChangeEntry('Уведомления: старые пуш-уведомления очищаются при запуске', ChangeType.bugfix),
      ChangeEntry('Уведомления задач и заметок больше не пересекаются', ChangeType.bugfix),
      ChangeEntry('Заметки в Obsidian не затирают файлы с одинаковыми именами', ChangeType.bugfix),
      ChangeEntry('Пользовательские чекбоксы в Obsidian больше не удаляются', ChangeType.bugfix),
      ChangeEntry('Если в задаче указано только время и оно уже прошло — день выбираете сами в редакторе', ChangeType.bugfix),
      ChangeEntry('Убрана авто-подстановка пути к vault с ПК на телефоне', ChangeType.bugfix),
      ChangeEntry('Синхронизация не виснет при больших объёмах данных', ChangeType.improvement),
      ChangeEntry('Исправлен запуск приложения: сплеш-экран больше не перезапускает приложение', ChangeType.bugfix),
      ChangeEntry('Сплеш-анимация без жёлтого подчёркивания под буквами', ChangeType.bugfix),
    ],
  ),
  ReleaseInfo(
    version: '1.2.18',
    date: '19.08.2026',
    changes: [
      ChangeEntry('Кастомная тема: свой фон и цвет текста через палитру', ChangeType.feature),
      ChangeEntry('Четыре режима темы: системная, светлая, тёмная, своя', ChangeType.feature),
      ChangeEntry('Мини-календарь текущего месяца на правой панели (ПК)', ChangeType.feature),
      ChangeEntry('Исправлен краш палитры цвета (IntrinsicWidth)', ChangeType.bugfix),
      ChangeEntry('Задачи без даты теперь видны в любом дне', ChangeType.bugfix),
      ChangeEntry('Улучшена сплеш-анимация', ChangeType.improvement),
      ChangeEntry('Полностью убрана статистика', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.2.17',
    date: '17.08.2026',
    changes: [
      ChangeEntry('Повторяющиеся задачи появляются автоматически каждый день', ChangeType.feature),
      ChangeEntry('Для повторяющихся задач не нужна дата — ставится автоматически', ChangeType.feature),
      ChangeEntry('Сравнение месяцев в статистике', ChangeType.feature),
      ChangeEntry('Улучшено сообщение об ошибке при проверке обновлений', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.2.16',
    date: '17.08.2026',
    changes: [
      ChangeEntry('Исправлен баг дублирования повторяющихся задач', ChangeType.bugfix),
      ChangeEntry('Убраны кружочки заметок с календаря', ChangeType.bugfix),
      ChangeEntry('Быстрый ввод: добавлена кнопка отправки', ChangeType.feature),
      ChangeEntry('Главная страница: события перемещены вниз', ChangeType.improvement),
      ChangeEntry('Отключено случайное переключение вкладок свайпом', ChangeType.bugfix),
      ChangeEntry('Исправлено дублирование заметок дня', ChangeType.bugfix),
    ],
  ),
  ReleaseInfo(
    version: '1.2.15',
    date: '16.08.2026',
    changes: [
      ChangeEntry('После синхронизации подставляется путь к vault с ПК', ChangeType.improvement),
      ChangeEntry('Кнопка «Сайт KHS» спрашивает подтверждение', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.2.14',
    date: '16.08.2026',
    changes: [
      ChangeEntry('Починено обновление по Wi-Fi (404)', ChangeType.bugfix),
      ChangeEntry('Публичный промо-сайт KHS на GitHub Pages', ChangeType.feature),
      ChangeEntry('В настройках — кнопка «Сайт KHS»', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.13',
    date: '16.08.2026',
    changes: [
      ChangeEntry('Экран «Статистика»: дневная цель, столбики, графики', ChangeType.feature),
      ChangeEntry('Кнопки создания задачи и заметки в календаре', ChangeType.feature),
      ChangeEntry('Фильтр задач по приоритету', ChangeType.feature),
      ChangeEntry('Линейные бары прогресса в сайдбаре', ChangeType.feature),
      ChangeEntry('Исправлен курсор в палитре цвета', ChangeType.bugfix),
    ],
  ),
  ReleaseInfo(
    version: '1.2.12',
    date: '16.08.2026',
    changes: [
      ChangeEntry('Светлая и тёмная тема', ChangeType.feature),
      ChangeEntry('Исправлен курсор в палитре выбора цвета', ChangeType.bugfix),
      ChangeEntry('Убрана надпись «Задач на этот день нет»', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.2.11',
    date: '16.08.2026',
    changes: [
      ChangeEntry('Исправлена история «Что нового» на телефоне', ChangeType.bugfix),
      ChangeEntry('Исправлен поиск файла обновления на ПК', ChangeType.bugfix),
      ChangeEntry('Исправлено выделение текста в заметке', ChangeType.bugfix),
      ChangeEntry('Заметки переносятся в Obsidian', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.10',
    date: '16.08.2026',
    changes: [
      ChangeEntry('Настройки уведомлений: «Работа в фоне» и «Точный будильник»', ChangeType.feature),
      ChangeEntry('Тестовое уведомление через 10 секунд', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.9',
    date: '16.08.2026',
    changes: [
      ChangeEntry('Быстрое переключение между vault', ChangeType.feature),
      ChangeEntry('Выбор папки vault на телефоне', ChangeType.feature),
      ChangeEntry('Обновление по Wi-Fi с понятными ошибками', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.2.8',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Переключение вкладок свайпом', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.7',
    date: '15.08.2026',
    changes: [
      ChangeEntry('На телефоне прячется системная панель', ChangeType.improvement),
      ChangeEntry('Новые задачи напоминают в срок по умолчанию', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.6',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Выбор времени: два вертикальных колеса', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.5',
    date: '15.08.2026',
    changes: [
      ChangeEntry('На телефоне кнопки добавления прозрачные', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.2.4',
    date: '15.08.2026',
    changes: [
      ChangeEntry('На ПК убрана плавающая кнопка', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.2.3',
    date: '15.08.2026',
    changes: [
      ChangeEntry('На ПК убраны кнопки-заглушки', ChangeType.improvement),
      ChangeEntry('Исправлен серый фон экранов', ChangeType.bugfix),
    ],
  ),
  ReleaseInfo(
    version: '1.2.2',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Навигация внизу: Главная, Календарь, Заметки, Настройки', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.1',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Удобный выбор времени задачи', ChangeType.feature),
      ChangeEntry('Кнопка обновления по Wi-Fi', ChangeType.feature),
      ChangeEntry('Цвет темы меняется на любой', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.2.0',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Автосохранение заметок', ChangeType.feature),
      ChangeEntry('Корзина заметок', ChangeType.feature),
      ChangeEntry('Помощь при «ПК не найден»', ChangeType.improvement),
    ],
  ),
  ReleaseInfo(
    version: '1.1.1',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Исправлена синхронизация телефон↔ПК', ChangeType.bugfix),
    ],
  ),
  ReleaseInfo(
    version: '1.1.0',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Синхронизация телефона с ПК по Wi-Fi', ChangeType.feature),
      ChangeEntry('Заметки синхронизируются с Obsidian', ChangeType.feature),
      ChangeEntry('Уведомления о новых заметках', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.0.2',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Исправлено сохранение заметки дня', ChangeType.bugfix),
    ],
  ),
  ReleaseInfo(
    version: '1.0.1',
    date: '15.08.2026',
    changes: [
      ChangeEntry('Заметка дня пишется в Obsidian', ChangeType.feature),
      ChangeEntry('Календарь: подсветка дней с заметками', ChangeType.feature),
    ],
  ),
  ReleaseInfo(
    version: '1.0.0',
    date: '14.08.2026',
    changes: [
      ChangeEntry('Трёхпанельный дашборд', ChangeType.feature),
      ChangeEntry('Заметки: заметка дня и отдельные', ChangeType.feature),
      ChangeEntry('Группы и теги задач', ChangeType.feature),
      ChangeEntry('Синхронизация с Obsidian', ChangeType.feature),
      ChangeEntry('Напоминания и уведомления', ChangeType.feature),
      ChangeEntry('Календарь и планирование', ChangeType.feature),
    ],
  ),
];

int compareVersions(String a, String b) {
  final pa = a.split('.').map(int.tryParse).whereType<int>().toList();
  final pb = b.split('.').map(int.tryParse).whereType<int>().toList();
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

ReleaseInfo? get latestRelease =>
    khsReleases.isEmpty ? null : khsReleases.first;

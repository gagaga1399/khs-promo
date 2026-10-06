import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

/// Набор цветов карточного интерфейса.
///
/// Отдельный класс, а не только константы, потому что один и тот же набор
/// виджетов работает в двух местах: на экранах настроек он берёт цвета темы
/// приложения, а во всплывающих панелях поверх страницы книги — цвета темы
/// самой книги. Структура палитры совпадает с `ReaderColors`, поэтому там
/// передача — одно присваивание.
@immutable
class SettingsPalette {
  const SettingsPalette({
    required this.background,
    required this.card,
    required this.text,
    required this.muted,
    required this.divider,
    required this.accent,
  });

  /// Фон экрана.
  final Color background;

  /// Фон карточки.
  final Color card;

  /// Основной текст.
  final Color text;

  /// Второстепенный текст.
  final Color muted;

  /// Разделитель.
  final Color divider;

  /// Акцент: стрелка «назад», фокус поля.
  final Color accent;

  static SettingsPalette of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Фон, карточка, текст и разделитель берём из темы приложения. Раньше
    // здесь стояли зашитые чёрный и тёмно-серый, и выбор темы в настройках
    // не доходил до самих настроек: при красной теме они оставались чёрными.
    // Акцент тоже из темы — он настраивается пользователем.
    return SettingsPalette(
      background: theme.scaffoldBackgroundColor,
      card: scheme.surfaceContainerHigh,
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      divider: scheme.outline,
      accent: scheme.primary,
    );
  }

  /// Палитра тёмной темы из ТЗ: чёрный фон, тёмно-серые карточки.
  static const SettingsPalette darkPalette = SettingsPalette(
    background: SettingsTokens.darkBackground,
    card: SettingsTokens.darkCard,
    text: SettingsTokens.darkText,
    muted: SettingsTokens.darkTextMuted,
    divider: SettingsTokens.darkDivider,
    accent: SettingsTokens.accentBlue,
  );

  /// Светлая тема. Фон не белый: у KHS тёплая палитра, и чистый белый на ней
  /// выглядит как дыра. Карточка светлее фона — так же, как в тёмной теме
  /// карточка темнее.
  static const SettingsPalette lightPalette = SettingsPalette(
    background: SettingsTokens.lightBackground,
    card: SettingsTokens.lightCard,
    text: SettingsTokens.lightText,
    muted: SettingsTokens.lightTextMuted,
    divider: SettingsTokens.lightDivider,
    accent: SettingsTokens.accentBlue,
  );

  /// Палитра под экран, лежащий на чёрном фоне приложения.
  SettingsPalette withAccent(Color value) => SettingsPalette(
    background: background,
    card: card,
    text: text,
    muted: muted,
    divider: divider,
    accent: value,
  );
}

/// Карточный тёмный интерфейс настроек.
///
/// Описание, по которому сделан набор: фон сплошной чёрный, смысловые блоки
/// собраны в карточки тёмно-серого, у каждой иконки свой цвет. Геометрия из
/// ТЗ: поля экрана 16, зазор между карточками 16–20, радиус карточки ~18,
/// внутренние отступы 16 по горизонтали и 12–16 по вертикали.
///
/// Токены лежат здесь, а не в `AppTheme`: `AppTheme` описывает приложение
/// целиком, а этот набор нужен экранам настроек.
class SettingsTokens {
  const SettingsTokens._();

  // ---------- Геометрия ----------
  /// Поле от края экрана.
  static const double margin = 16;

  /// Зазор между карточками.
  static const double gap = 16;

  /// Радиус карточки.
  static const double radiusCard = 18;

  /// Внутренние отступы карточки по горизонтали.
  static const double padH = 16;

  /// Внутренние отступы карточки по вертикали.
  static const double padV = 6;

  /// Толщина разделителя.
  static const double dividerThickness = 1;

  /// Размер иконки пункта.
  static const double iconSize = 24;

  /// Отступ от иконки до текста.
  static const double iconGap = 14;

  /// Разделитель внутри карточки начинается там же, где текст, а не от края.
  static const double dividerInset = padH + iconSize + iconGap;

  // ---------- Тёмная палитра (из ТЗ) ----------
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkCard = Color(0xFF1C1C1E);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkTextMuted = Color(0xFF8E8E93);
  static const Color darkDivider = Color(0xFF2C2C2E);

  // ---------- Светлая палитра ----------
  static const Color lightBackground = Color(0xFFB9B6A8);
  static const Color lightCard = Color(0xFFEDEBE0);
  static const Color lightText = Color(0xFF1F1F1F);
  static const Color lightTextMuted = Color(0xFF6E6C62);
  static const Color lightDivider = Color(0xFFD2CFC2);

  /// Акцент по умолчанию, если тема не задала свой.
  static const Color accentBlue = Color(0xFF3D7BFD);

  // ---------- Палитра иконок (из ТЗ) ----------
  static const Color iconAppearance = Color(0xFF9C27B0); // Внешний вид
  static const Color iconMedia = Color(0xFF2196F3); // Медиатека
  static const Color iconMetadata = Color(0xFFFFC107); // Метаданные
  static const Color iconText = Color(0xFF00BCD4); // Тексты
  static const Color iconPlayback = Color(0xFF3F51B5); // Воспроизведение
  static const Color iconDownload = Color(0xFF4CAF50); // Скачивание
  static const Color iconFiles = Color(0xFFFF9800); // Файлы и папки
  static const Color iconStorage = Color(0xFF5C6BC0); // Хранилище
  static const Color iconBackup = Color(0xFF009688); // Резервирование
  static const Color iconLogs = Color(0xFF8D6E63); // Логи
  static const Color iconSupport = Color(0xFFE91E63); // Поддержка
  static const Color iconProfile = Color(0xFFF44336); // Профиль
  static const Color iconAccount = Color(0xFFAB47BC); // Аккаунт и вход
  static const Color iconSync = Color(0xFF26A69A); // Синхронизация
  static const Color iconAi = Color(0xFF7E57C2); // ИИ
  static const Color iconSecurity = Color(0xFFEF5350); // Безопасность
  static const Color iconNetwork = Color(0xFF42A5F5); // Сеть и сервер
  static const Color iconUpdate = Color(0xFF66BB6A); // Обновления
  static const Color iconNotes = Color(0xFFEC407A); // Заметки
  static const Color iconTasks = Color(0xFF29B6F6); // Задачи

  // ---------- Типографика ----------
  static const double titleSize = 26;
  static const double rowTitleSize = 16;
  static const double rowSubtitleSize = 14;
  static const double groupTitleSize = 13;

  /// Счётчик символов под полем ввода.
  static const double counterSize = 12;

  // ---------- Появление карточек ----------
  /// Насколько карточка выезжает снизу перед появлением. Большой сдвиг
  /// выглядит как рывок, поэтому он намеренно небольшой.
  static const double revealShift = 14;

  /// Длительность появления одной карточки. Короткая анимация читается
  /// как резкое переключение, поэтому берём с запасом.
  static const Duration revealDuration = Duration(milliseconds: 420);

  /// Пауза между соседними карточками каскада.
  static const Duration revealStagger = Duration(milliseconds: 45);

  /// Сколько карточек максимум получает задержку: у седьмой и дальше
  /// пауза уже не растёт, иначе низ списка появлялся бы слишком долго.
  static const int revealMaxStagger = 5;

  /// Насколько снизу экрана начинается появление, в долях высоты окна.
  /// Карточка должна успеть доехать до кадра незаметно, поэтому порог
  /// заметно выше нижней кромки.
  static const double revealLeadIn = 0.12;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      SettingsPalette.of(context).background;

  static Color card(BuildContext context) => SettingsPalette.of(context).card;

  static Color text(BuildContext context) => SettingsPalette.of(context).text;

  static Color muted(BuildContext context) => SettingsPalette.of(context).muted;

  static Color divider(BuildContext context) =>
      SettingsPalette.of(context).divider;

  /// Акцент интерфейса. В ТЗ стрелка «назад» красная, но там же сказано, что
  /// это акцентный цвет системы, поэтому берём акцент темы: у KHS он
  /// настраивается пользователем.
  static Color accent(BuildContext context) =>
      SettingsPalette.of(context).accent;

  /// Подложка нажатия: лёгкое осветление, без брызг.
  static Color pressOverlay(Color card) =>
      Color.alphaBlend(Colors.white.withValues(alpha: 0.07), card);

  // ---------- Нижняя панель действий ----------
  /// Порог прокрутки, после которого панель действий появляется.
  static const double actionBarRevealOffset = 24;

  /// Высота панели действий вместе с отступами.
  static const double actionBarHeight = 68;

  /// Длительность появления/скрытия панели действий.
  static const Duration actionBarDuration = Duration(milliseconds: 220);
}

/// Контроллер прокрутки с приглушённой чувствительностью.
///
/// Длинный список настроек при прокрутке колесом и трекпадом пролетал мимо
/// нужного пункта: один «щелчок» колеса съедал пол-экрана. Здесь гасится
/// только шаг колеса — сама физика остаётся прежней.
///
/// Приглушать перетаскивание пальцем нельзя: `applyUserOffset` вызывается и
/// при касании, и список на телефоне ехал вполсилы, список казалось «залипал».
/// Инерция после броска тоже не гасится — на телефоне палец отпускают, а
/// список должен долететь как обычно.
class SettingsScrollController extends ScrollController {
  SettingsScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.stepScale = 0.55,
  });

  /// Насколько слабее реагирует список на колесо и на трекпад.
  final double stepScale;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _WheelDampedScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      oldPosition: oldPosition,
      keepScrollOffset: keepScrollOffset,
      debugLabel: debugLabel,
      stepScale: stepScale,
    );
  }
}

/// Позиция прокрутки, которая приглушает только колесо.
class _WheelDampedScrollPosition extends ScrollPositionWithSingleContext {
  _WheelDampedScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    required this.stepScale,
  });

  final double stepScale;

  /// Вызывается на каждое событие колеса и трекпада.
  @override
  void pointerScroll(double delta) {
    super.pointerScroll(delta * stepScale);
  }
}

/// Экран настроек целиком: чёрный фон, крупный заголовок, необязательный
/// поиск и прокручиваемое содержимое из карточек.
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.title,
    required this.children,
    this.onBack,
    this.search,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      SettingsTokens.margin,
      0,
      SettingsTokens.margin,
      SettingsTokens.margin,
    ),
    this.controller,
    this.actions,
  });

  final String title;
  final List<Widget> children;

  /// Если null — стрелки «назад» нет: экран открыт как вкладка или окно без
  /// навигации назад.
  final VoidCallback? onBack;

  final Widget? search;

  /// Кнопки справа в шапке.
  final Widget? trailing;

  final EdgeInsets padding;

  /// Внешний контроллер прокрутки. Если не задан, используется
  /// [SettingsScrollController] — с приглушённой чувствительностью.
  final ScrollController? controller;

  /// Кнопки в нижней панели, которая появляется только после прокрутки
  /// списка вниз. Если не задана, панели нет вовсе.
  final Widget? actions;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  /// Свой контроллер нужен, чтобы приглушить прокрутку, и его надо dispose.
  /// Внешний контроллер не трогаем — его жизненный цикл у владельца.
  late final ScrollController _controller;
  late final bool _ownsController;

  /// Показывает ли нижнюю панель действий. Панель нужна только когда список
  /// уже прокручен: наверху она бесполезна и закрывает первый экран.
  bool _actionsVisible = false;

  /// Ключи карточек: по ним измеряем, какая карточка дошла до экрана.
  late final List<GlobalKey> _revealKeys = [
    for (var i = 0; i < widget.children.length; i++) GlobalKey(),
  ];

  /// Уже показанные карточки. Проявлять их повторно нельзя: список
  /// перестраивается при каждом кадре анимации прокрутки.
  final Set<int> _revealed = <int>{};

  /// Проверка уже запланирована на следующий кадр.
  bool _revealScheduled = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? SettingsScrollController(debugLabel: 'settings');
    _controller.addListener(_onScroll);
    // Первый экран не должен ждать прокрутки: после первого кадра
    // показываем всё, что уже помещается в окно.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRevealCheck());
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final show = _controller.offset > SettingsTokens.actionBarRevealOffset;
    if (show != _actionsVisible) {
      setState(() => _actionsVisible = show);
    }
    _scheduleRevealCheck();
  }

  /// Проверка видимости откладывается до конца кадра: во время build
  /// размеры ещё не применены и карточка «невидима» ошибочно.
  void _scheduleRevealCheck() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted) return;
      final visible = _collectVisible();
      if (visible.isEmpty) return;
      setState(() => _revealed.addAll(visible));
    });
  }

  /// Номера карточек, которые вот-вот попадут в кадр. Порог снизу, а не
  /// сверху: карточка должна начать появляться до того, как доедет до
  /// нижней кромки, иначе она «выпрыгивает» из-под края экрана.
  Set<int> _collectVisible() {
    final result = <int>{};
    if (_revealed.length >= widget.children.length) return result;
    final screenH = MediaQuery.sizeOf(context).height;
    final leadIn = screenH * SettingsTokens.revealLeadIn;
    for (var i = 0; i < widget.children.length; i++) {
      if (_revealed.contains(i)) continue;
      final box = _revealKeys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top < screenH - leadIn) result.add(i);
    }
    return result;
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SettingsPalette.of(context);
    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsHeader(
              title: widget.title,
              onBack: widget.onBack,
              trailing: widget.trailing,
              palette: palette,
            ),
            if (widget.search case final field?) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SettingsTokens.margin,
                ),
                child: field,
              ),
            ],
            Expanded(
              child: ListView(
                controller: _controller,
                // Короткий список должен всё равно оттягиваться при скролле.
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                // Место под нижнюю панель, иначе последняя карточка уходит
                // под неё и не доходит до конца списка.
                padding: widget.actions != null
                    ? widget.padding.add(
                        const EdgeInsets.only(
                          bottom: SettingsTokens.actionBarHeight,
                        ),
                      )
                    : widget.padding,
                // Единый вертикальный зазор между карточками: нельзя полагаться
                // на отступы внутри самих карточек, иначе соседние группы
                // прилипают друг к другу.
                children: <Widget>[
                  for (var i = 0; i < widget.children.length; i++) ...[
                    if (i > 0) const SizedBox(height: SettingsTokens.gap),
                    // Проявление карточки запускает родитель: он же знает
                    // контроллер прокрутки. Сама карточка только рисует
                    // анимацию, когда флаг `revealed` переключается в true.
                    SettingsReveal(
                      key: _revealKeys[i],
                      index: i,
                      revealed: _revealed.contains(i),
                      palette: palette,
                      child: widget.children[i],
                    ),
                  ],
                ],
              ),
            ),
            if (widget.actions case final bar?)
              SettingsActionBar(
                visible: _actionsVisible,
                palette: palette,
                child: bar,
              ),
          ],
        ),
      ),
    );
  }
}

/// Крупный заголовок с акцентной стрелкой «назад» слева.
///
/// Пустой [title] — заголовок не рисуется вовсе. Так убирается дубль слова
/// «Настройки» на вкладке, которая уже подписана в нижней навигации.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.palette,
    this.stackedTitle = true,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final SettingsPalette? palette;

  /// По ТЗ заголовок расположен под кнопкой «Назад». В узких местах
  /// (например, поверх страницы книги) его можно поставить в одну строку.
  final bool stackedTitle;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    final titleText = title.trim().isEmpty
        ? null
        : Text(
            title,
            style: TextStyle(
              fontSize: SettingsTokens.titleSize,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          );
    final backButton = onBack == null
        ? null
        : Tooltip(
            message: MaterialLocalizations.of(context).backButtonTooltip,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onBack,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStatePropertyAll(
                  SettingsTokens.pressOverlay(p.background),
                ),
                // Хит-зона 40x40, но сама иконка прижата к левому краю поля:
                // у IconButton вокруг иконки пустая зона, из-за которой стрелка
                // уезжает вправо от заголовка под ней.
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: 20,
                      // Раньше брался акцент темы, а он может совпадать с
                      // фоном — стрелка тогда просто исчезала.
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
    final margin = EdgeInsets.fromLTRB(
      SettingsTokens.margin,
      4,
      SettingsTokens.margin,
      stackedTitle ? 12 : 8,
    );
    if (!stackedTitle || backButton == null) {
      return Padding(
        padding: margin,
        child: Row(
          children: [
            if (backButton != null) ...[
              backButton,
              const SizedBox(width: 4),
            ] else
              const SizedBox(width: 32),
            if (titleText != null) Expanded(child: titleText),
            ?trailing,
          ],
        ),
      );
    }
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [backButton, ?trailing]),
          if (titleText != null) ...[const SizedBox(height: 2), titleText],
        ],
      ),
    );
  }
}

/// Нижняя панель действий настроек.
///
/// Пока список не прокручен, панель скрыта — наверху она только занимает
/// место и закрывает верхний край первого экрана. Как только пользователь
/// прокрутил список вниз, панель выезжает снизу и держит кнопки под рукой.
/// При прокрутке наверх панель снова прячется, чтобы не мешать.
class SettingsActionBar extends StatelessWidget {
  const SettingsActionBar({
    super.key,
    required this.visible,
    required this.child,
    this.palette,
  });

  /// Показывать ли панель.
  final bool visible;

  final Widget child;
  final SettingsPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    return AnimatedSlide(
      duration: SettingsTokens.actionBarDuration,
      curve: Curves.easeOutCubic,
      // Скрытое состояние уводит панель за нижний край окна.
      offset: visible ? Offset.zero : const Offset(0, 1),
      child: AnimatedOpacity(
        duration: SettingsTokens.actionBarDuration,
        curve: Curves.easeOut,
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            decoration: BoxDecoration(
              color: p.background,
              border: Border(
                top: BorderSide(
                  color: p.divider,
                  width: SettingsTokens.dividerThickness,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              SettingsTokens.margin,
              10,
              SettingsTokens.margin,
              10,
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(height: 40, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Обёртка для содержимого [SettingsActionBar]: кнопки во всю ширину.
class SettingsActionBarButton extends StatelessWidget {
  const SettingsActionBarButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.palette,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SettingsPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SettingsTokens.radiusCard),
          ),
        ),
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

/// Поисковая «пилюля».
class SettingsSearch extends StatelessWidget {
  const SettingsSearch({
    super.key,
    required this.hint,
    this.onChanged,
    this.controller,
    this.palette,
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final SettingsPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: p.text, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.muted, fontSize: 15),
          filled: true,
          fillColor: p.card,
          prefixIcon: Icon(Icons.search, size: 20, color: p.muted),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: p.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Подзаголовок группы: маленькая подпись над карточкой.
class SettingsGroupTitle extends StatelessWidget {
  const SettingsGroupTitle(this.title, {super.key, this.palette});

  final String title;
  final SettingsPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, SettingsTokens.gap, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: SettingsTokens.groupTitleSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: p.muted,
        ),
      ),
    );
  }
}

/// Карточка со списком пунктов и разделителями.
///
/// Разделитель между пунктами-соседями начинается с отступа, где начинается
/// текст, а не от края карточки. Между произвольным содержимым (поля ввода,
/// ползунки) разделитель идёт от внутреннего поля — иначе он повисает в
/// пустоте.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.children,
    this.title,
    this.padding,
    this.palette,
  });

  final List<Widget> children;

  /// Подзаголовок группы над карточкой.
  final String? title;

  /// Отступы вокруг содержимого. По умолчанию карточка «обтягивает» пункты
  /// [SettingsRow] вплотную, а произвольному содержимому достаются поля.
  final EdgeInsets? padding;

  final SettingsPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    final hasRow = children.whereType<SettingsRow>().isNotEmpty;
    final inner =
        padding ??
        (hasRow
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(
                horizontal: SettingsTokens.padH,
                vertical: SettingsTokens.padV,
              ));

    final body = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        final inset =
            children[i - 1] is SettingsRow && children[i] is SettingsRow
            ? SettingsTokens.dividerInset
            : SettingsTokens.padH;
        body.add(
          Padding(
            padding: EdgeInsets.only(left: inset),
            child: Divider(
              height: SettingsTokens.dividerThickness,
              thickness: SettingsTokens.dividerThickness,
              color: p.divider,
            ),
          ),
        );
      }
      body.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) SettingsGroupTitle(title!, palette: p),
        Material(
          color: p.card,
          borderRadius: BorderRadius.circular(SettingsTokens.radiusCard),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: inner,
            child: Column(children: body),
          ),
        ),
      ],
    );
  }
}

/// Пункт настроек: цветная иконка, название, необязательная подпись, шеврон.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.dense = false,
    this.palette,
  });

  final String title;
  final IconData? icon;

  /// Свой цвет у каждой иконки — ради этого всё и затевалось.
  final Color? iconColor;

  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Шеврон серой стрелкой вправо.
  final bool showChevron;

  /// Компактная высота: для переключателей и выпадающих списков.
  final bool dense;

  final SettingsPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    final leading = icon == null
        ? null
        : SizedBox(
            width: SettingsTokens.iconSize,
            height: SettingsTokens.iconSize,
            child: Icon(
              icon,
              size: SettingsTokens.iconSize,
              color: iconColor ?? p.accent,
            ),
          );

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: SettingsTokens.padH,
        vertical: dense ? 8 : 12,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: SettingsTokens.iconGap),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: SettingsTokens.rowTitleSize,
                    height: 1.25,
                    color: p.text,
                  ),
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: SettingsTokens.rowSubtitleSize,
                      height: 1.3,
                      color: p.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ] else if (showChevron && onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 22, color: p.muted),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      // В ТЗ — лёгкое осветление фона, а не брызги.
      splashFactory: NoSplash.splashFactory,
      overlayColor: WidgetStatePropertyAll(SettingsTokens.pressOverlay(p.card)),
      child: content,
    );
  }
}

/// Карточка профиля: иконка человека, две строки текста, шеврон.
class SettingsProfileCard extends StatelessWidget {
  const SettingsProfileCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.icon = Icons.account_circle,
    this.iconColor,
    this.palette,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final IconData icon;

  /// По ТЗ иконка профиля красная, но обычно берётся акцент темы.
  final Color? iconColor;

  final SettingsPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    final tint = iconColor ?? SettingsTokens.iconProfile;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(SettingsTokens.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStatePropertyAll(
          SettingsTokens.pressOverlay(p.card),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SettingsTokens.padH,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(icon, size: 34, color: tint),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: SettingsTokens.rowSubtitleSize,
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 24, color: tint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Появление карточки настроек при прокрутке.
///
/// Пока родитель ([SettingsView]) не добавил свой номер в [revealed],
/// карточка скрыта. Само появление — плавный выезд снизу с ростом
/// прозрачности; задержка каскада считается от [index], поэтому верхние
/// карточки не ждут друг друга.
///
/// Обнаруживать видимость внутри виджета нельзя: `ScrollNotification`
/// всплывает от `Scrollable` вверх и до его детей не доходит, поэтому
/// проверку ведёт родитель, у которого есть контроллер прокрутки.
class SettingsReveal extends StatefulWidget {
  const SettingsReveal({
    super.key,
    required this.child,
    required this.index,
    required this.revealed,
    this.palette,
  });

  final Widget child;

  /// Номер карточки в списке: задаёт паузу каскада.
  final int index;

  /// Пока родитель не признал карточку видимой, она скрыта. Флаг именно
  /// логический: общий набор номеров сравнивался бы сам с собой, и
  /// `didUpdateWidget` не заметил бы появления.
  final bool revealed;

  final SettingsPalette? palette;

  @override
  State<SettingsReveal> createState() => _SettingsRevealState();
}

class _SettingsRevealState extends State<SettingsReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  /// Пауза каскада задаётся не таймером, а отрезком внутри анимации:
  /// иначе после закрытия экрана остаётся висящий таймер, а в тестах
  /// это роняет проверку «нет незавершённых таймеров».
  @override
  void initState() {
    super.initState();
    final step = widget.index > SettingsTokens.revealMaxStagger
        ? SettingsTokens.revealMaxStagger
        : widget.index;
    final delay = SettingsTokens.revealStagger * step;
    final total = delay + SettingsTokens.revealDuration;
    _controller = AnimationController(vsync: this, duration: total);
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
    if (widget.revealed) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant SettingsReveal old) {
    super.didUpdateWidget(old);
    if (old.revealed || !widget.revealed) return;
    if (_controller.isCompleted) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, SettingsTokens.revealShift * (1 - _curve.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Поле ввода внутри карточки: без резкой обводки, заливка темнее карточки.
class SettingsField extends StatefulWidget {
  const SettingsField({
    super.key,
    this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.controller,
    this.onChanged,
    this.suffix,
    this.prefixIcon,
    this.focusNode,
    this.autofocus = false,
    this.palette,
    this.maxLength,
  });

  final String? label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final Widget? prefixIcon;
  final FocusNode? focusNode;
  final bool autofocus;
  final SettingsPalette? palette;

  /// Максимум символов. Если задан, под полем появляется счётчик
  /// «12 / 100», который краснеет у лимита.
  final int? maxLength;

  @override
  State<SettingsField> createState() => _SettingsFieldState();
}

class _SettingsFieldState extends State<SettingsField> {
  /// Текущая длина текста для счётчика. Держим здесь, потому что
  /// `TextField.maxLength` сам счётчик не рисует, а внешний rebuild по
  /// `onChanged` перестраивал бы всё поле на каждый символ.
  int _length = 0;

  @override
  void initState() {
    super.initState();
    _length = widget.controller?.text.characters.length ?? 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Контроллер мог подставить значение после первого кадра.
    final text = widget.controller?.text;
    if (text != null) _length = text.characters.length;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final hint = widget.hint;
    final obscureText = widget.obscureText;
    final keyboardType = widget.keyboardType;
    final maxLines = widget.maxLines;
    final controller = widget.controller;
    final onChanged = widget.onChanged;
    final suffix = widget.suffix;
    final prefixIcon = widget.prefixIcon;
    final focusNode = widget.focusNode;
    final autofocus = widget.autofocus;
    final maxLength = widget.maxLength;
    final p = widget.palette ?? SettingsPalette.of(context);
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      onChanged: (v) {
        setState(() => _length = v.characters.length);
        onChanged?.call(v);
      },
      autofocus: autofocus,
      style: TextStyle(color: p.text, fontSize: 15),
      decoration: settingsInputDecoration(
        context,
        label: label,
        hint: hint,
        suffix: suffix,
        prefixIcon: prefixIcon,
        palette: p,
        // Свой счётчик рисуется под полем, встроенный убираем: иначе
        // у поля оказывается два счётчика с разным начертанием.
        counterText: maxLength == null ? null : '',
      ),
    );
    if (maxLength == null) return field;
    // Встроенный счётчик Material рисуется рамкой вокруг поля и ломает
    // вид карточки, поэтому заменяем его своим, под полем.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        SettingsFieldCounter(length: _length, maxLength: maxLength, palette: p),
      ],
    );
  }
}

/// Счётчик символов под полем ввода.
///
/// Сам по себе не обновляется: значение [length] приходит от владельца поля,
/// который перестраивает виджет по `onChanged`.
class SettingsFieldCounter extends StatelessWidget {
  const SettingsFieldCounter({
    super.key,
    required this.length,
    required this.maxLength,
    this.palette,
  });

  final int length;
  final int maxLength;
  final SettingsPalette? palette;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? SettingsPalette.of(context);
    final left = maxLength - length;
    // У лимита подсветка становится акцентной: оставшийся резерв виден
    // раньше, чем ввод упрётся в стену.
    final tight = left <= maxLength ~/ 5;
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 2),
      child: Text(
        '$length / $maxLength',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: SettingsTokens.counterSize,
          color: tight ? p.accent : p.muted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Декор поля, общий для [SettingsField] и выпадающих списков: иначе поля
/// ввода и списки в одном экране выглядят как из разных приложений.
InputDecoration settingsInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? helper,
  Widget? suffix,
  Widget? prefixIcon,
  SettingsPalette? palette,
  String? counterText,
}) {
  final p = palette ?? SettingsPalette.of(context);
  // Заливка поля темнее карточки в тёмной теме и светлее в светлой.
  final fill = SettingsTokens.isDark(context)
      ? Color.alphaBlend(Colors.black.withValues(alpha: 0.35), p.card)
      : Color.alphaBlend(Colors.white.withValues(alpha: 0.6), p.card);

  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: 1),
  );

  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: p.muted),
    hintText: hint,
    hintStyle: TextStyle(color: p.muted),
    helperText: helper,
    helperStyle: TextStyle(color: p.muted, fontSize: 12),
    filled: true,
    fillColor: fill,
    suffixIcon: suffix,
    prefixIcon: prefixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    counterText: counterText,
    border: border(p.divider),
    enabledBorder: border(p.divider),
    focusedBorder: border(p.accent),
  );
}

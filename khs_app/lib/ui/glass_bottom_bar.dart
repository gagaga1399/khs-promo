import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Высота плавающей панели.
const double kGlassNavHeight = 74;

/// Отступы панели от краёв экрана: по бокам и снизу.
const double kGlassNavMarginX = 18;
const double kGlassNavMarginBottom = 16;

/// Запас сверху и снизу капсулы для «пилюли», которая в переходе растёт до
/// 132% высоты и выходит за рамку. Взято по максимуму роста (74 × 0.32 / 2),
/// чтобы в покое запас не выглядел пустым отступом.
const double kGlassNavOverflow = 12;

/// На широком окне панель не растягивается во всю ширину, а остаётся
/// «капсулой» посередине.
const double kGlassNavMaxWidth = 520;

/// Ключи для тестов: по ним видно, где именно капсула и где «пилюля», не
/// гадая по типам виджетов (их в дереве много одинаковых).
const Key kGlassNavCapsuleKey = Key('glass-nav-capsule');
const Key kGlassNavPillKey = Key('glass-nav-pill');
const String kGlassNavSlotLabelKeyPrefix = 'glass-nav-slot-label-';

/// Ключ слоя прорисовки акцента: он есть только пока идёт hover-анимация.
const String kGlassNavWipeKeyPrefix = 'glass-nav-wipe-';

/// Оттенок подложки панели. Матовый фон = полупрозрачный: сквозь него
/// просвечивает содержимое под панелью размытыми пятнами, поэтому заливка
/// всегда идёт с альфой. В тёмной теме оттенок светлее экрана, в светлой —
/// темнее, чтобы панель читалась как отдельная поверхность.
const Color kGlassNavDarkBase = Color(0xFF3A3A3A);
const Color kGlassNavLightBase = Color(0xFFB9B6A8);

/// Плотность подложки: меньше 1 — просвечивает, 1 — глухая заливка.
const double kGlassNavMatteAlpha = 0.64;

/// Акцентная обводка пилюли для заданного раздувания. Возвращает null в покое:
/// обводки в состоянии покоя нет, она проявляется только на раздутой пилюле и
/// гаснет вместе с ней. Вынесено отдельно от painter, чтобы тест проверял те
/// же числа, что рисуются на экране.
///
/// [accent] берётся из темы, поэтому обводка перекрашивается вместе с
/// приложением.
({double width, Color color})? kGlassNavPillOutline(
  double swell,
  Color accent,
) {
  if (swell <= 0.001) return null;
  return (
    width: 1.0 + 1.4 * swell,
    color: accent.withValues(alpha: 0.55 * swell),
  );
}

/// Доля панели, по которой «прорисовывается» акцент при наведении.
const double kGlassNavHoverBand = 0.45;

/// Пружина вместо готовой кривой.
///
/// SpotiFLAC гоняет переходы через `motion` со spring-параметрами stiffness
/// 50–250 и damping 10–25: движение слегка доскакивает и затухает, а не
/// приходит по дуге. Здесь та же физика, но переведённая в [Curve], чтобы
/// контроллер остался 0→1 и раздувание пилюли по-прежнему зависело от
/// нормализованного прогресса.
///
/// Параметры 280/24 дают перелёт около 4% хода. Важно, что перелёт
/// масштабируется от длины прыжка, а не абсолютный: при переходе через один
/// пункт это ~6px, через два — ~11px. При stiffness 210 и damping 17 перелёт
/// был 17%, то есть на длинном прыжке пилюля уезжала за цель на четверть
/// панели. Перелёт у края панели срезается ограничением диапазона, поэтому в
/// двух крайних пунктах пружина визуально не перелетает.
///
/// Кривая строится выборкой [SpringSimulation] и повторяет её кусочно-
/// линейно, поэтому даёт настоящее перелётное движение, а не имитацию.
class SpringCurve extends Curve {
  SpringCurve({
    this.mass = 1,
    this.stiffness = 280,
    this.damping = 24,
    this.samples = 121,
  }) {
    final sim = SpringSimulation(
      SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
      0,
      1,
      0,
    );
    final settle = _settleTime(sim);
    _table = List<double>.generate(
      samples,
      (i) => sim.x((i / (samples - 1)) * settle),
      growable: false,
    );
  }

  final double mass;
  final double stiffness;
  final double damping;
  final int samples;

  late final List<double> _table;

  /// Время, за которое пружина считается остановившейся.
  static double _settleTime(SpringSimulation sim) {
    const dt = 1 / 240;
    var t = 0.0;
    while (t < 4) {
      t += dt;
      if ((sim.x(t) - 1).abs() < 0.0005 && sim.dx(t).abs() < 0.0005) break;
    }
    return t;
  }

  @override
  double transformInternal(double t) {
    if (t <= 0) return _table.first;
    if (t >= 1) return _table.last;
    final x = t * (_table.length - 1);
    final i = x.floor();
    final f = x - i;
    return _table[i] + (_table[i + 1] - _table[i]) * f;
  }
}

/// Пункт плавающей нижней панели.
class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Плавающая нижняя панель навигации: полупрозрачная матовая поверхность с
/// мягкой тенью. Подложка всегда с альфой, сквозь неё просвечивает содержимое
/// под панелью размытыми пятнами. Оттенок в тёмной теме светлее экрана, в
/// светлой — темнее.
///
/// При переключении «пилюля» активного пункта не просто переезжает, а
/// раздувается и на время выходит за рамку капсулы, после чего оседает
/// обратно. Движение идёт по пружине, поэтому пилюля слегка перелетает
/// конечную точку и доезжает. Высота анимации задана жёстко: в
/// bottomNavigationBar ограничение по высоте неограниченное, и виджеты, которые
/// тянутся (Center, Expanded), растянули бы панель так, что она оказалась бы
/// посередине экрана.
///
/// При наведении акцент «прорисовывается» по иконке диагональной полосой, как
/// в SpotiFLAC: иконки там анимируются через pathLength и pathOffset, а сами
/// штрихи полоски звука пульсируют каждый со своим периодом. Здесь то же
/// ощущение сделано заливкой акцентом, потому что иконки Material — это
/// глифы шрифта, а не контуры, и анимировать длину пути у них нечем.
///
/// Если в системе включено «уменьшить анимацию», все переходы происходят
/// мгновенно: это [MediaQuery.disableAnimations].
class GlassBottomBar extends StatefulWidget {
  const GlassBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.hidden = false,
    this.onBack,
  });

  final List<GlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Капсула уезжает вниз за экран, а [onBack] (если задан) показывает на её
  /// месте кнопку возврата. Высота виджета при этом не меняется: тело экрана
  /// не дёргается, а место уходящей капсулы не пустует.
  final bool hidden;

  /// Обязателен вместе с [hidden], иначе уйти будет некуда.
  final VoidCallback? onBack;

  @override
  State<GlassBottomBar> createState() => _GlassBottomBarState();
}

class _GlassBottomBarState extends State<GlassBottomBar>
    with TickerProviderStateMixin {
  /// Движение заканчивается на 62% анимации, оставшееся время отдано
  /// раздуванию: пилюля доезжает и ещё доливает себя, затем оседает.
  static const double _moveFraction = 0.62;
  static const double _maxSwell = 0.32;

  /// Пружина перехода. damping 17 при stiffness 210 даёт заметный, но короткий
  /// перелёт — «живой» характер без желе.
  static final SpringCurve _move = SpringCurve(stiffness: 280, damping: 24);

  /// Прорисовка акцента при наведении: короче и мягче перехода пилюли.
  static const int _hoverMs = 260;

  /// Уход капсулы вниз и её возврат. Разные кривые по направлению: уходит
  /// бодро, возвращается мягко — так не теряется ощущение, куда она делась.
  static const int _hideMs = 420;
  static final Curve _hideAway = Curves.easeInCubic;
  static final Curve _hideBack = Curves.easeOutCubic;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final AnimationController _hoverC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _hoverMs),
  );
  late final AnimationController _hideC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _hideMs),
  );

  /// Откуда пилюля едет. Это double, а не индекс: при прерывании перехода
  /// стартовать надо из фактической позиции, а не из предыдущей цели, иначе
  /// пилюля телепортируется к старой цели и только потом едет к новой.
  double _fromPos = 0;

  /// Куда пилюля едет.
  int _toIndex = 0;

  /// Раздувание, унаследованное от прерванного перехода, и насколько сильно
  /// раздуваемся в текущем. Нужны, чтобы прерывание не было видно скачком:
  /// в момент прерывания раздувание не обнуляется, а плавно затухает.
  double _swellOffset = 0;
  double _swellPeak = 1;

  /// Пункты, между которыми едет прорисовка акцента: из `_hoverFrom` в
  /// `_hoverTo`. Значение -1 означает «не рисуем».
  int _hoverFrom = -1;
  int _hoverTo = -1;

  /// В системе включено «уменьшить анимацию».
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _fromPos = widget.currentIndex.toDouble();
    _toIndex = widget.currentIndex;
    // Стартовое значение, а не animate: панель не должна проезжать мимо
    // экрана при первой сборке, если сразу открыли настройки.
    if (widget.hidden) _hideC.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    // Порядок вызовов важен: Flutter сначала зовёт didUpdateWidget, и только
    // потом didChangeDependencies. Значит в didUpdateWidget флаг «уменьшить
    // анимацию» ещё старый, и переход успел бы запуститься. Здесь приводим
    // уход к конечному значению сразу — анимации при включённом «уменьшить
    // анимацию» быть не должно.
    if (_reduceMotion) _hideC.value = widget.hidden ? 1 : 0;
  }

  /// Логическая позиция пилюли на моменте [value] контроллера.
  ///
  /// Пружина даёт перелёт, но позиция ограничена диапазоном пунктов: иначе на
  /// переходе с первого на последний пилюля на перелёте уезжала бы за капсулу.
  double _posAt(double value, int n) {
    final raw = value / _moveFraction;
    final t = _move.transform(raw < 0 ? 0.0 : (raw > 1 ? 1.0 : raw));
    final pos = _fromPos + (_toIndex - _fromPos) * t;
    return pos < 0 ? 0 : (pos > n - 1 ? n - 1 : pos);
  }

  /// Раздувание на моменте [value]: ноль в начале и в конце перехода.
  double _swellAt(double value) =>
      _swellOffset * (1 - value) + math.sin(math.pi * value) * _swellPeak;

  @override
  void didUpdateWidget(covariant GlassBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncHide(oldWidget);
    if (widget.currentIndex == _toIndex) return;
    // Переход мог быть прерван на лету, поэтому стартовая точка — это где
    // пилюля реально находится, а не предыдущий пункт меню.
    final fromNow = _posAt(_c.value, widget.items.length);
    final swellNow = _swellAt(_c.value);
    _fromPos = fromNow;
    _toIndex = widget.currentIndex;
    _swellOffset = swellNow;
    _swellPeak = 1 - swellNow;
    if (_reduceMotion) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  /// Запускает уход или возврат капсулы. Значение `value` считается по
  /// направлению движения, а не по одному `Curves` на обе стороны.
  void _syncHide(GlassBottomBar oldWidget) {
    if (widget.hidden == oldWidget.hidden) return;
    if (_reduceMotion) {
      _hideC.value = widget.hidden ? 1 : 0;
      return;
    }
    if (widget.hidden) {
      _hideC.forward(from: _hideC.value);
    } else {
      _hideC.reverse(from: _hideC.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _hoverC.dispose();
    _hideC.dispose();
    super.dispose();
  }

  void _tap(int i) {
    HapticFeedback.selectionClick();
    if (i != widget.currentIndex) widget.onTap(i);
  }

  void _setHover(int i) {
    if (_hoverTo == i) return;
    setState(() {
      _hoverFrom = _hoverTo;
      _hoverTo = i;
    });
    if (_reduceMotion) {
      _hoverC.value = 1;
    } else {
      _hoverC.forward(from: 0);
    }
  }

  /// Насколько акцент «прорисован» в пункте [i] на текущем кадре: 0 — иконка
  /// серая, 1 — полностью акцентная.
  double _wipeOf(int i) {
    if (i == widget.currentIndex) return 1;
    if (_hoverC.isDismissed) {
      return i == _hoverTo ? 1 : 0;
    }
    final t = Curves.easeInOut.transform(_hoverC.value);
    if (i == _hoverTo) return t;
    if (i == _hoverFrom) return 1 - t;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Акцент из темы: панель должна перекрашиваться вместе с приложением, а не
    // держать свой собственный цвет.
    final accent = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: kGlassNavMarginBottom),
      child: SizedBox(
        // Нижнее поле учитывается SafeArea выше, здесь только сама капсула с
        // запасом под раздувающуюся пилюлю.
        height: kGlassNavHeight + kGlassNavOverflow * 2,
        child: AnimatedBuilder(
          // Список merge обновлён: у капсулы теперь три независимых движения —
          // переезд пилюли, прорисовка акцента и уход вниз.
          animation: Listenable.merge([_c, _hoverC, _hideC]),
          builder: (context, _) {
            // Уезжаем дальше своей высоты, иначе край капсулы остался бы
            // висеть в кадре. Высота виджета не меняется — тело экрана не
            // дёргается, а освободившееся место занимает кнопка возврата.
            final drop = kGlassNavHeight + kGlassNavOverflow * 2 + 24;
            // Прогресс считаем один раз: геттер запоминает направление
            // движения, и два обращения подряд в одном кадре дали бы разные
            // кривые для сдвига и прозрачности.
            final away = _hideT;
            return Stack(
              children: [
                Transform.translate(
                  offset: Offset(0, drop * away),
                  child: Opacity(
                    opacity: 1 - away,
                    child: _body(context, dark, accent),
                  ),
                ),
                if (widget.onBack != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: away,
                      child: Center(child: _backPill(widget.onBack!)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Насколько капсула уехала вниз: 0 — на месте, 1 — за экраном.
  ///
  /// Кривая выбирается по факту уменьшения значения, а не по статусу
  /// контроллера: при `reverse()` статус меняется не сразу, и на первых
  /// кадрах возврата применялась бы кривая ухода — уезжает бодро, но
  /// возвращается так же резво.
  double get _hideT {
    final returning = _hideC.value < _hideWas;
    _hideWas = _hideC.value;
    return (returning ? _hideBack : _hideAway).transform(_hideC.value);
  }

  /// Предыдущее значение прогресса ухода — чтобы отличить ход от возврата.
  double _hideWas = 0;

  /// Кнопка возврата на месте ушедшей капсулы. Без неё панель убирать нельзя:
  /// настройки открываются как вкладка, и возвращаться больше нечем.
  /// Подложка под стрелкой не нужна: на узком экране это лишнее серое поле,
  /// которое отвлекает от содержимого.
  Widget _backPill(VoidCallback onBack) {
    return Tooltip(
      message: MaterialLocalizations.of(context).backButtonTooltip,
      child: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () {
          HapticFeedback.selectionClick();
          onBack();
        },
      ),
    );
  }

  /// Вся прежняя начинка панели: капсула, пилюля и подписи. Вынесена из build,
  /// чтобы уход капсулы не переписывал её целиком в анимации уезда.
  Widget _body(BuildContext context, bool dark, Color accent) {
    const hPad = 8.0;
    final n = widget.items.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGlassNavMarginX),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kGlassNavMaxWidth),
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 8.0;
              final slot = math.max(
                0.0,
                (c.maxWidth - hPad * 2 - gap * (n - 1)) / n,
              );
              return AnimatedBuilder(
                animation: Listenable.merge([_c, _hoverC]),
                builder: (context, _) {
                  final pos = _posAt(_c.value, n);
                  // 0 в начале и в конце, 1 в середине перехода.
                  final swell = _swellAt(_c.value);
                  // Пилюля не должна становиться выше своей ширины. На
                  // телефоне слот (≈71 при 360dp) уже самой капсулы, и
                  // раздувание до 132% превращало её в вертикальный
                  // овал: 71×98 вместо 71×74. Поэтому рост по высоте
                  // ограничен шириной слота. На широком окне слот шире
                  // капсулы, ограничение не действует и анимация
                  // остаётся прежней.
                  final pillHeight = math.min(
                    kGlassNavHeight * (1 + _maxSwell * swell),
                    slot,
                  );
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: kGlassNavOverflow,
                        height: kGlassNavHeight,
                        child: _capsule(context, dark, accent, hPad, gap, slot),
                      ),
                      Positioned(
                        key: kGlassNavPillKey,
                        left: hPad + pos * (slot + gap),
                        top:
                            kGlassNavOverflow +
                            kGlassNavHeight / 2 -
                            pillHeight / 2,
                        width: slot,
                        height: pillHeight,
                        child: CustomPaint(
                          painter: _PressedPillPainter(
                            dark: dark,
                            accent: accent,
                            swell: swell,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _capsule(
    BuildContext context,
    bool dark,
    Color accent,
    double hPad,
    double gap,
    double slot,
  ) {
    final radius = BorderRadius.circular(kGlassNavHeight / 2);
    final n = widget.items.length;

    // Тень держим на внешнем слое: ClipRRect и BackdropFilter обрезают всё
    // внутри себя, поэтому тень на том же виджете была бы срезана.
    return DecoratedBox(
      key: kGlassNavCapsuleKey,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.50 : 0.18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // Матовость = полупрозрачность + размытие. Без размытия под панелью
          // просвечивала бы чёткая картинка, а не мягкие пятна.
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              // Подложка всегда полупрозрачная: элементы под панелью должны
              // просвечивать. Оттенок в тёмной теме светлее экрана, в светлой
              // темнее.
              color: (dark ? kGlassNavDarkBase : kGlassNavLightBase).withValues(
                alpha: kGlassNavMatteAlpha,
              ),
              // Рамка одноцветная — Flutter не даёт разные цвета разным
              // сторонам одной рамки.
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.10),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Row(
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    SizedBox(
                      width: slot,
                      child: _slot(context, i, dark, accent, kGlassNavHeight),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slot(
    BuildContext context,
    int index,
    bool dark,
    Color accent,
    double height,
  ) {
    final item = widget.items[index];
    final selected = index == widget.currentIndex;
    final muted = dark ? Colors.white70 : Colors.black54;

    return MouseRegion(
      onEnter: (_) => _setHover(index),
      onExit: (_) => _setHover(-1),
      child: InkWell(
        borderRadius: BorderRadius.circular(height / 2),
        onTap: () => _tap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: selected
                  ? BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.30),
                          blurRadius: 12,
                        ),
                      ],
                    )
                  : const BoxDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _wipeIcon(
                  context,
                  index,
                  accent: accent,
                  muted: muted,
                  selected: selected,
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                color: selected || _wipeOf(index) > 0.5 ? accent : muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(
                item.label,
                key: Key('$kGlassNavSlotLabelKeyPrefix$index'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Иконка с прорисовкой акцента по наведению.
  ///
  /// Иконки Material — глифы шрифта, поэтому анимировать `pathLength`, как в
  /// SpotiFLAC, нечем. Поэтому прорисовка сделана заливкой: серая иконка лежит
  /// снизу, акцентная сверху, а сверху маска-полоса, которая едет по диагонали.
  /// Вместе это читается как обводка акцентом и работает с любым `IconData`.
  Widget _wipeIcon(
    BuildContext context,
    int index, {
    required Color accent,
    required Color muted,
    required bool selected,
  }) {
    final item = widget.items[index];
    final wipe = _wipeOf(index);
    // Под наведением иконка чуть больше, у активного пункта — заметнее.
    final scale = wipe > 0.5 || selected ? 1.10 : 1.0 + 0.06 * wipe;
    final glyph = Icon(
      selected ? item.activeIcon : item.icon,
      size: 24,
      color: wipe >= 0.999 ? accent : muted,
    );

    // Пока прорисовки нет, не держим в дереве лишний слой: серая иконка
    // достаточно. Стек собирается только на время анимации.
    final Widget child;
    if (wipe <= 0) {
      child = glyph;
    } else if (wipe >= 0.999) {
      child = Icon(
        selected ? item.activeIcon : item.icon,
        size: 24,
        color: accent,
      );
    } else {
      child = Stack(
        alignment: Alignment.center,
        children: [
          Icon(item.icon, size: 24, color: muted),
          ShaderMask(
            key: Key('$kGlassNavWipeKeyPrefix$index'),
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [Colors.white, Colors.white],
              stops: [
                (wipe - kGlassNavHoverBand).clamp(0.0, 1.0),
                (wipe + kGlassNavHoverBand).clamp(0.0, 1.0),
              ],
            ).createShader(rect),
            child: Icon(
              selected ? item.activeIcon : item.icon,
              size: 24,
              color: accent,
            ),
          ),
        ],
      );
    }

    return AnimatedScale(
      scale: scale,
      duration: Duration(milliseconds: _reduceMotion ? 0 : 240),
      curve: Curves.easeOutCubic,
      child: SizedBox.square(dimension: 24, child: child),
    );
  }
}

/// «Вдавленная» таблетка активного пункта: заливка темнее фона панели плюс
/// внутренняя тень по краю. Внутренней тени в Flutter нет, поэтому рисуем
/// размытую обводку той же формы и обрезаем её по внутреннему контуру.
class _PressedPillPainter extends CustomPainter {
  _PressedPillPainter({
    required this.dark,
    required this.accent,
    this.swell = 0,
  });

  final bool dark;

  /// Акцент из темы — обводка в переходе должна быть того же цвета, что
  /// иконка и подпись активного пункта.
  final Color accent;

  /// Насколько пилюля раздута в текущий момент: 0 — покой, 1 — пик перехода.
  final double swell;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = dark
            ? Colors.black.withValues(alpha: 0.34 + 0.10 * swell)
            : Colors.black.withValues(alpha: 0.06 + 0.04 * swell),
    );

    canvas.save();
    canvas.clipRRect(rrect);
    // Обводка смещена вниз: тень гуще снизу, сверху светлее — выглядит
    // вдавленным.
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black.withValues(alpha: dark ? 0.45 : 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();

    // Тонкий светлый ободок по верхней кромке.
    if (dark) {
      canvas.drawRRect(
        rrect.shift(const Offset(0, 1.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.10 + 0.14 * swell)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // Акцентная обводка появляется только на раздутой пилюле: в покое её
    // нет, в переходе толщина и прозрачность растут вместе с раздуванием и
    // гаснут обратно. Так видно, где «нажата» таблетка.
    final outline = kGlassNavPillOutline(swell, accent);
    if (outline != null) {
      canvas.drawRRect(
        rrect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = outline.width
          ..color = outline.color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PressedPillPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.accent != accent ||
      oldDelegate.swell != swell;
}

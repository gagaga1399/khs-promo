import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'glass_bottom_bar.dart';
import 'widgets/aurora_grid.dart';
import 'widgets/quick_add_bar.dart';

/// Тег Hero панели быстрого ввода: она перелетает между списком задач
/// («2 экран») и подстраницей быстрого ввода.
const String kQuickAddHeroTag = 'quick-add';

/// Подстраница раздела «Задачи» (вкладка «Главная»): быстрый ввод задачи.
///
/// На фоне живёт декоративное сияние, заголовок «KHS Task» всплывает плавно и
/// растягивается по буквам, а по центру — панель быстрого ввода. Снизу
/// остаётся только нижняя панель навигации.
class TaskQuickCaptureScreen extends StatefulWidget {
  const TaskQuickCaptureScreen({super.key, required this.onSelectTab});

  final ValueChanged<int> onSelectTab;

  @override
  State<TaskQuickCaptureScreen> createState() => _TaskQuickCaptureScreenState();
}

class _TaskQuickCaptureScreenState extends State<TaskQuickCaptureScreen>
    with TickerProviderStateMixin {
  /// Декор: сияние плывёт по экрану без остановки.
  late final AnimationController _aurora = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  /// Вступление намеренно долгое: заголовок появляется неспешно, «с растягом».
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..forward();

  @override
  void dispose() {
    _aurora.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final accent = state.accentColor;

    final appear = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.85, curve: Curves.easeOutCubic),
    );

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _aurora,
                  builder: (context, _) => CustomPaint(
                    painter: AuroraBackPainter(
                      t: _aurora.value,
                      accent: accent,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: appear,
                      child: AnimatedBuilder(
                        animation: appear,
                        builder: (context, _) => Text(
                          'KHS Task',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -4 + 16 * appear.value,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Hero(
                      tag: kQuickAddHeroTag,
                      child: const QuickAddBar(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: GlassBottomBar(
        currentIndex: 0,
        onTap: (i) {
          Navigator.of(context).maybePop();
          if (i != 0) widget.onSelectTab(i);
        },
        items: [
          GlassNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: strings.t('home'),
          ),
          GlassNavItem(
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month,
            label: strings.t('calendar'),
          ),
          GlassNavItem(
            icon: Icons.book_outlined,
            activeIcon: Icons.book,
            label: strings.t('notes'),
          ),
          GlassNavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            label: strings.t('settings'),
          ),
        ],
      ),
    );
  }
}

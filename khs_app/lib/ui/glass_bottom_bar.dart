import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Пункт стеклянной нижней панели.
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

/// Нижняя панель навигации «как в Spotify»: размывает содержимое экрана под
/// собой, активный пункт подсвечивается «пилюлей», которая плавно
/// переезжает при переключении.
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<GlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final bar = LayoutBuilder(
      builder: (context, c) {
        final n = items.length;
        final floating = c.maxWidth >= 720;
        final hPad = floating ? 16.0 : 10.0;
        final gap = 6.0;
        final inner = c.maxWidth - hPad * 2;
        final slot = (inner - gap * (n - 1)) / n;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            hPad,
            floating ? 12 : 6,
            hPad,
            floating ? 12 : 0,
          ),
          child: SizedBox(
            height: 62,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: currentIndex * (slot + gap),
                  top: 0,
                  bottom: 0,
                  width: slot,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(22),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.35)),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      SizedBox(
                        width: slot,
                        child: _slot(context, i, dark, accent),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    final base = dark ? const Color(0xFF0C0C0F) : const Color(0xFFFFFFFF);
    final line = (dark ? Colors.white : Colors.black).withValues(alpha: 0.10);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: base.withValues(alpha: dark ? 0.45 : 0.55),
            border: Border(top: BorderSide(color: line)),
          ),
          child: SafeArea(top: false, child: bar),
        ),
      ),
    );
  }

  Widget _slot(
    BuildContext context,
    int index,
    bool dark,
    Color accent,
  ) {
    final item = items[index];
    final selected = index == currentIndex;
    final muted = dark ? Colors.white70 : Colors.black54;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        HapticFeedback.selectionClick();
        if (index != currentIndex) onTap(index);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Icon(
              selected ? item.activeIcon : item.icon,
              size: 24,
              color: selected ? accent : muted,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              color: selected ? accent : muted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

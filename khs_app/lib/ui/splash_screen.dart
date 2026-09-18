import 'dart:async';

import 'package:flutter/material.dart';

import 'hub_screen.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _startAnimation();
  }

  Future<void> _startAnimation() async {
    _ctrl.forward();
    await Future.delayed(const Duration(milliseconds: 3500));
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F7F9),
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => _buildScene(constraints.maxWidth),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScene(double screenW) {
    final t = _ctrl.value;

    final fontSize = (screenW < 400 ? 36.0 : 56.0);
    final spreadMax = screenW < 400 ? 14.0 : 36.0;

    final spreadT = _phase(0.0, 0.55, t);
    final spread = Curves.easeOutCubic.transform(spreadT);
    final dx = spreadMax * spread;

    final kStyle = TextStyle(
      color: const Color(0xFF15151B),
      fontFamily: 'Segoe UI',
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    final restStyle = TextStyle(
      color: const Color(0xFF5A5A66),
      fontFamily: 'Segoe UI',
      fontSize: fontSize * 0.28,
      fontWeight: FontWeight.w400,
      letterSpacing: 2,
    );
    const subStyle = TextStyle(
      color: Color(0xFF9A9AA6),
      fontFamily: 'Segoe UI',
      fontSize: 13,
      letterSpacing: 5,
      fontWeight: FontWeight.w400,
      decoration: TextDecoration.none,
    );

    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Transform.translate(
                offset: Offset(-dx, 0),
                child: Text('K', style: kStyle),
              ),
              Text('H', style: kStyle),
              Transform.translate(
                offset: Offset(dx, 0),
                child: Text('S', style: kStyle),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Kill Habitual Structure',
            style: restStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 26),
          const Text('Task Manager', style: subStyle),
        ],
      );
  }

  static double _phase(double start, double end, double t) {
    if (t <= start) return 0.0;
    if (t >= end) return 1.0;
    return (t - start) / (end - start);
  }
}

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  var _done = false;

  void _finish() {
    if (!mounted) return;
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    return _done
        ? const HubScreen()
        : SplashScreen(onComplete: _finish);
  }
}

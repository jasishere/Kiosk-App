import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/logo_badge.dart';

/// The attract screen. This is what the kiosk displays for the overwhelming
/// majority of its runtime, which drives two decisions:
///
///  - One orchestrated entrance, then stillness. The old version ran a
///    14-particle CustomPainter and a shimmer sweep on repeating controllers
///    that never stopped, so an idle kiosk repainted at 60fps indefinitely.
///    On a passively-cooled Pi 5 behind glass that is real heat for
///    decoration nobody is watching.
///  - One unmistakable target. Everything else is quiet.
class WelcomeStep extends StatefulWidget {
  const WelcomeStep({super.key});

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Animation<double> _stage(double begin, double end) => CurvedAnimation(
        parent: _entrance,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KioskController>();
    final mark = _stage(0.0, 0.55);
    final word = _stage(0.25, 0.8);
    final cta = _stage(0.55, 1.0);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: mark,
              child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(mark),
                child: const LogoBadge(size: 120),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            FadeTransition(
              opacity: word,
              child: Column(
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -2.2,
                        height: 1.0,
                        fontFamily: 'Roboto',
                      ),
                      children: [
                        TextSpan(
                          text: 'Coin',
                          style: TextStyle(color: AppColors.green),
                        ),
                        TextSpan(
                          text: 'vert',
                          style: TextStyle(color: AppColors.gold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Break a bill or build one up, in seconds',
                    style: AppText.body.copyWith(fontSize: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xxl),
            FadeTransition(
              opacity: cta,
              child: _StartTarget(onTap: controller.startTransaction),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single oversized target. Sized well past the touch minimum because this
/// is the one control a first-time user has to find from a few metres away.
class _StartTarget extends StatefulWidget {
  final VoidCallback onTap;
  const _StartTarget({required this.onTap});

  @override
  State<_StartTarget> createState() => _StartTargetState();
}

class _StartTargetState extends State<_StartTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Material(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // One recognizer. The old build stacked a GestureDetector over an
          // InkWell, which put two arena members on the same tap — whichever
          // won was not stable across rebuilds, so the start button could
          // silently stop responding after a full transaction cycle.
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.xxl,
              vertical: AppSpace.lg,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Touch to start',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(width: AppSpace.md),
                Icon(Icons.arrow_forward, color: Colors.white, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

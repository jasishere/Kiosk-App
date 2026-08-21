import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/colors.dart';
import '../state/kiosk_controller.dart';
import '../widgets/logo_badge.dart';
import '../widgets/welcome_decor.dart';

class WelcomeStep extends StatefulWidget {
  const WelcomeStep({super.key});

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep>
    with TickerProviderStateMixin {
  // Staggered entrance: logo scales/fades in first, wordmark and subtitle
  // fade-slide up shortly after, then the CTA fades in.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  // Gentle continuous "breathing" once things have landed — the whole
  // logo group drifts up/down a couple px and the CTA's glow pulses.
  // Idle motion, not attention-grabbing, so the screen still feels alive
  // while someone decides to walk up and tap it.
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  // Momentary press feedback on the CTA.
  bool _pressed = false;

  Animation<double> _fadeSlide(double startFraction, double endFraction) =>
      CurvedAnimation(
        parent: _entrance,
        curve: Interval(startFraction, endFraction, curve: Curves.easeOutCubic),
      );

  @override
  void dispose() {
    _entrance.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KioskController>();
    final logoAnim = _fadeSlide(0.0, 0.55);
    final textAnim = _fadeSlide(0.35, 0.8);
    final ctaAnim = _fadeSlide(0.65, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale the whole composition off the available height so it
        // fills a tall kiosk panel instead of huddling at a fixed size
        // with dead space around it, while staying sane on a smaller
        // preview frame.
        final scale = (constraints.maxHeight / 560).clamp(0.85, 1.55);
        double s(double v) => v * scale;

        return Stack(
          children: [
            // Faint security-paper dot texture across the whole step —
            // felt more than seen.
            Positioned.fill(
              child: CustomPaint(
                painter: DotGridPainter(
                  color: AppColors.textPrimary.withValues(alpha: 0.025),
                  spacing: s(22),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 0.55, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _entrance,
                          curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
                        ),
                      ),
                      child: FadeTransition(
                        opacity: logoAnim,
                        child: AnimatedBuilder(
                          animation: _idle,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(0, -_idle.value * s(5)),
                            child: child,
                          ),
                          child: LogoBadge(size: s(96), animate: true),
                        ),
                      ),
                    ),
                    SizedBox(height: s(14)),
                    FadeTransition(
                      opacity: textAnim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(textAnim),
                        child: Column(
                          children: [
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: s(54),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.6,
                                  height: 1.0,
                                ),
                                children: const [
                                  TextSpan(
                                      text: 'COIN', style: TextStyle(color: AppColors.green)),
                                  TextSpan(
                                      text: 'VERT', style: TextStyle(color: AppColors.goldDark)),
                                ],
                              ),
                            ),
                            SizedBox(height: s(12)),
                            FlankedLabel(
                              text: 'SMART CURRENCY EXCHANGE',
                              fontSize: s(12.5),
                              gap: s(10),
                              ruleWidth: s(20),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: s(34)),
                    FadeTransition(
                      opacity: ctaAnim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.4),
                          end: Offset.zero,
                        ).animate(ctaAnim),
                        child: AnimatedBuilder(
                          animation: _idle,
                          builder: (context, child) {
                            final glow = 0.22 + _idle.value * 0.18;
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(s(16)),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.green.withValues(alpha: glow),
                                    blurRadius: s(24) + _idle.value * s(10),
                                    spreadRadius: _idle.value * s(1.5),
                                  ),
                                ],
                              ),
                              child: child,
                            );
                          },
                          child: GestureDetector(
                            onTapDown: (_) => setState(() => _pressed = true),
                            onTapCancel: () => setState(() => _pressed = false),
                            onTapUp: (_) => setState(() => _pressed = false),
                            child: AnimatedScale(
                              scale: _pressed ? 0.96 : 1.0,
                              duration: const Duration(milliseconds: 110),
                              curve: Curves.easeOut,
                              child: TicketButton(
                                label: 'TAP TO START',
                                onPressed: controller.startTransaction,
                                fontSize: s(15),
                                iconSize: s(19),
                                paddingH: s(34),
                                paddingV: s(18),
                                radius: s(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Coinvert logo, built from three layers cut from the source artwork
/// (registered in pubspec.yaml under flutter -> assets):
///   - assets/coinvert_base.png         (coin + card, static)
///   - assets/coinvert_arrow_green.png  (the green arrow only)
///   - assets/coinvert_arrow_gold.png   (the gold/orange arrow only)
/// All three share the same 240x240 canvas as the original artwork, so
/// they stack with no offset math.
///
/// When [animate] is true, the two arrows swing back and forth about
/// 28° along their own arc — like a needle nudging forward and
/// re-cocking — rather than spinning a full 360°. A full spin looks
/// wrong here because each arrow is a partial arc with a head pointing
/// one way: rotate it all the way around and the head sweeps through
/// every direction, which reads as broken rather than cyclical. The
/// swing is also capped well short of a half turn so the green and gold
/// arrows never rotate far enough to overlap and visually merge into
/// each other. Set [animate] to false for static contexts (e.g. small
/// icons in lists).
class LogoBadge extends StatefulWidget {
  final double size;
  final bool animate;
  const LogoBadge({super.key, this.size = 58, this.animate = true});

  @override
  State<LogoBadge> createState() => _LogoBadgeState();
}

class _LogoBadgeState extends State<LogoBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _cycle.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant LogoBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_cycle.isAnimating) {
      _cycle.repeat(reverse: true);
    } else if (!widget.animate && _cycle.isAnimating) {
      _cycle.stop();
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  Widget _arrow(String asset) => Image.asset(
        asset,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      );

  @override
  Widget build(BuildContext context) {
    final base = Image.asset(
      'assets/coinvert_base.png',
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
    );

    if (!widget.animate) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            base,
            _arrow('assets/coinvert_arrow_green.png'),
            _arrow('assets/coinvert_arrow_gold.png'),
          ],
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _cycle,
        builder: (context, _) {
          // Swing far enough to clearly read as motion, but capped well
          // short of a half turn so the two arrows never rotate into
          // each other's space and visually merge at the top.
          final t = Curves.easeInOut.transform(_cycle.value);
          final swing = (t - 0.5) * 2 * (28 * math.pi / 180);
          return Stack(
            alignment: Alignment.center,
            children: [
              base,
              Transform.rotate(angle: swing, child: _arrow('assets/coinvert_arrow_green.png')),
              Transform.rotate(angle: -swing, child: _arrow('assets/coinvert_arrow_gold.png')),
            ],
          );
        },
      ),
    );
  }
}

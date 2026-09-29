import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The Coinvert mark.
///
/// Renders the layered brand artwork when it is bundled:
///   assets/coinvert_base.png
///   assets/coinvert_arrow_green.png
///   assets/coinvert_arrow_gold.png
/// all sharing the original 240×240 canvas, so they stack with no offset.
///
/// If any layer is missing it falls back to a drawn mark instead of throwing.
/// An unresolved asset is a *runtime* exception in Flutter, not a build
/// error, so a mis-set pubspec would previously have taken out the welcome
/// screen only once it reached the kiosk — which is exactly where you cannot
/// fix it. The fallback keeps the machine serviceable.
class LogoBadge extends StatelessWidget {
  final double size;
  const LogoBadge({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/coinvert_base.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _FallbackMark(size: size),
        // Layers on top only make sense if the base resolved, so they are
        // composed inside the frameBuilder rather than stacked blindly.
        frameBuilder: (context, child, frame, wasSync) {
          return Stack(
            alignment: Alignment.center,
            children: [
              child,
              _layer('assets/coinvert_arrow_green.png'),
              _layer('assets/coinvert_arrow_gold.png'),
            ],
          );
        },
      ),
    );
  }

  Widget _layer(String asset) => Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
}

/// Two interlocking arrows in the brand colours — enough to read as the mark
/// if the artwork is ever missing.
class _FallbackMark extends StatelessWidget {
  final double size;
  const _FallbackMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ExchangeMarkPainter(),
    );
  }
}

class _ExchangeMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * 0.36;
    final stroke = size.width * 0.11;

    final rect = Rect.fromCircle(center: center, radius: radius);

    void arc(Color color, double startDeg, double sweepDeg) {
      canvas.drawArc(
        rect,
        startDeg * math.pi / 180,
        sweepDeg * math.pi / 180,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    arc(AppColors.green, 150, 160);
    arc(AppColors.gold, -30, 160);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// A dashed circle, used to build the concentric "exchange dial" behind
/// the logo. Deliberately hand-rolled (dart:ui has no dash-path helper)
/// so it stays dependency-free.
class DashedRingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;
  final double dashFraction; // 0..1 of each segment that's "on"
  final double rotation; // radians

  DashedRingPainter({
    required this.color,
    this.strokeWidth = 1.4,
    this.dashCount = 28,
    this.dashFraction = 0.55,
    this.rotation = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - strokeWidth;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final segment = (2 * math.pi) / dashCount;
    final on = segment * dashFraction;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (int i = 0; i < dashCount; i++) {
      final start = rotation + i * segment;
      canvas.drawArc(rect, start, on, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DashedRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.rotation != rotation;
}

/// Very faint dot-grid, the texture of security paper / thermal receipt
/// stock. Static, cheap, and only meant to be felt, not seen directly.
class DotGridPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double dotRadius;

  DotGridPainter({
    required this.color,
    this.spacing = 22,
    this.dotRadius = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotGridPainter oldDelegate) => false;
}

/// The welcome screen's call to action, styled like a torn ticket stub —
/// two punched notches at the ends — since this kiosk's whole job is
/// handing people a token of value. Deliberately distinct from the plain
/// [PrimaryButton] used mid-flow.
class TicketButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final double fontSize;
  final double iconSize;
  final double paddingH;
  final double paddingV;
  final double radius;
  const TicketButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fontSize = 14,
    this.iconSize = 18,
    this.paddingH = 30,
    this.paddingV = 16,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.green, Color(0xFF255E29)],
            ),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(width: paddingH * 0.3),
                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: iconSize),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short hairline-flanked label, e.g. "— SMART CURRENCY EXCHANGE —",
/// used in place of a plain caption for a more considered, signage-like
/// feel.
class FlankedLabel extends StatelessWidget {
  final String text;
  final double fontSize;
  final double gap;
  final double ruleWidth;
  const FlankedLabel({
    super.key,
    required this.text,
    this.fontSize = 11,
    this.gap = 10,
    this.ruleWidth = 18,
  });

  @override
  Widget build(BuildContext context) {
    final rule = Container(
      width: ruleWidth,
      height: 1,
      color: AppColors.textSecondary.withValues(alpha: 0.35),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        rule,
        SizedBox(width: gap),
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 2.4,
          ),
        ),
        SizedBox(width: gap),
        rule,
      ],
    );
  }
}

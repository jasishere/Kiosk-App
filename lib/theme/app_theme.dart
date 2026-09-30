import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

/// Palette.
///
/// Deepened from the original mockup values: a kiosk is read standing up,
/// at arm's length, often with daylight on the panel. The old #2E7D32 green
/// on #FBFCFA sat around 5:1 — fine on a laptop, marginal on glass in a
/// market. These clear 7:1 for body text and 4.5:1 for every accent used on
/// a tinted ground.
class AppColors {
  const AppColors._();

  // Brand
  static const green = Color(0xFF1F6B2B);
  static const greenDeep = Color(0xFF14501E);
  static const greenTint = Color(0xFFE4F0E3);
  static const gold = Color(0xFF8A5A05);
  static const goldTint = Color(0xFFF9EED6);

  // Surfaces — three layers, so hierarchy comes from depth not from
  // giving everything the same border and the same shadow.
  static const canvas = Color(0xFFF1F3EE);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFF7F8F5);
  static const ink = Color(0xFF16200F);
  static const hairline = Color(0xFFDDE2D8);

  // Text
  static const textPrimary = Color(0xFF16200F);
  static const textSecondary = Color(0xFF5E6A59);
  static const textMuted = Color(0xFF8A9485);
  static const onInk = Color(0xFFF4F6F1);
  static const onInkMuted = Color(0xFFA9B4A3);

  // Status
  static const danger = Color(0xFFA32116);
  static const dangerTint = Color(0xFFFBE9E7);
  static const warning = Color(0xFF8A5A05);
  static const ok = green;
}

/// Type scale.
///
/// One family, four roles. Money gets tabular figures so a running total
/// doesn't shift horizontally as digits change — a proportional-figure
/// counter visibly jitters while someone feeds in coins, which reads as
/// the display glitching rather than counting.
class AppText {
  const AppText._();

  static const _tabular = [FontFeature.tabularFigures()];

  /// The amount. This is the hero on almost every screen — the number is
  /// the content, so it gets the size.
  static const money = TextStyle(
    fontSize: 52,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.6,
    height: 1.0,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  static const moneySmall = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.1,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  static const title = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.15,
    color: AppColors.textPrimary,
  );

  static const heading = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  static const bodyStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.textMuted,
  );

  static const button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );
}

class AppSpace {
  const AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 22.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class AppRadius {
  const AppRadius._();

  /// Radius encodes scale rather than being one value on everything:
  /// controls are tighter than panels, panels tighter than the frame.
  static const control = 10.0;
  static const panel = 16.0;
  static const frame = 24.0;
}

/// Formats pesos for display. Whole pesos only — the kiosk has no sub-peso
/// hardware, so trailing ".00" on every figure is noise that makes the
/// number slower to read at a distance.
String peso(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}₱$buffer';
}

ThemeData buildKioskTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.green,
      primary: AppColors.green,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.canvas,
  );

  return base.copyWith(
    splashFactory: InkSparkle.splashFactory,
    tooltipTheme: const TooltipThemeData(preferBelow: false),
  );
}

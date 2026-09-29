import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Minimum touch target. Public kiosks are used with wet hands, gloves, and
/// by people who can't see the panel well; 44pt is a floor, not a target.
const double kTouchTarget = 56;

/// The one action that moves the flow forward on a screen. Never more than
/// one of these visible at a time.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = false,
    this.height = kTouchTarget,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    final button = SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.hairline,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: AppText.button),
            if (icon != null) ...[
              const SizedBox(width: AppSpace.sm),
              Icon(icon, size: 20),
            ],
          ],
        ),
      ),
    );

    // Disabled state is communicated by colour, not by a live-looking button
    // that swallows taps — the old build passed an empty closure when the
    // minimum wasn't met, so the button looked enabled and did nothing.
    return Opacity(
      opacity: enabled ? 1 : 0.85,
      child: fullWidth ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Secondary action — present but visually subordinate.
class QuietButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;

  const QuietButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      height: kTouchTarget,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.hairline),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: Text(
          label,
          style: AppText.button.copyWith(fontSize: 15),
        ),
      ),
    );

    return fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Large stepper control for the custom-mix picker.
class StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const StepperButton({super.key, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: enabled ? AppColors.greenTint : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Icon(
            icon,
            size: 22,
            color: enabled ? AppColors.green : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

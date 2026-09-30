import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';

/// Overlay for incidents *inside* a transaction — a payout that did not
/// finish, or an amount that cannot be assembled.
///
/// Standing outages are not shown here; those get their own step, because an
/// overlay implies a dismissable event and there is nothing the customer can
/// dismiss about a dead controller board.
///
/// Every message ends with what happens to the customer's money. That is the
/// only question anyone actually has when a cash machine stops mid-way.
class ErrorOverlay extends StatelessWidget {
  const ErrorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final error = context.select<KioskController, KioskError>((c) => c.error);
    // IgnorePointer, not a bare SizedBox: this sits under a Positioned.fill,
    // so it is stretched to the whole panel whether or not it draws
    // anything, and must be explicit about letting touches through.
    if (error == KioskError.none) {
      return const IgnorePointer(child: SizedBox.expand());
    }

    final controller = context.read<KioskController>();
    final detail = controller.errorDetail;
    final paid = controller.dispensedSoFar.entries
        .fold<int>(0, (sum, e) => sum + e.key.value * e.value);
    final owed = controller.amountInserted - paid;

    return ColoredBox(
      color: AppColors.ink.withValues(alpha: 0.94),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(error), size: 48, color: AppColors.onInk),
                const SizedBox(height: AppSpace.md),
                Text(
                  _title(error),
                  style: AppText.title.copyWith(color: AppColors.onInk),
                ),
                if (detail != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    detail,
                    style: AppText.body.copyWith(
                      color: AppColors.onInkMuted,
                      fontSize: 17,
                    ),
                  ),
                ],
                if (owed > 0) ...[
                  const SizedBox(height: AppSpace.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Text(
                      'You are still owed ${peso(owed)}. Please show this '
                      'screen to the attendant — the kiosk has recorded it.',
                      style: AppText.bodyStrong.copyWith(color: Colors.white),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.xl),
                PrimaryButton(
                  label: 'I understand',
                  onPressed: controller.dismissError,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _icon(KioskError error) => switch (error) {
        KioskError.dispenseFailed => Icons.error_outline,
        KioskError.planUnavailable => Icons.help_outline,
        KioskError.none => Icons.check,
      };

  String _title(KioskError error) => switch (error) {
        KioskError.dispenseFailed => 'The payout did not finish',
        KioskError.planUnavailable => 'We cannot make that amount',
        KioskError.none => '',
      };
}

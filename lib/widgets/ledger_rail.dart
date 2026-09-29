import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/kiosk_step.dart';
import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';

/// The running record of the customer's money, fixed in one place for the
/// whole transaction: what went in, what the fee is, what comes out.
///
/// Modelled on the paper slip a money changer writes in front of you — the
/// point is that the arithmetic is visible and never moves, so nobody has to
/// take the machine's word for the final figure.
class LedgerRail extends StatelessWidget {
  const LedgerRail({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KioskController>();
    final step = controller.step;
    final inserted = controller.amountInserted;

    // Before the customer reaches the output step, show the plain
    // percentage fee. Only once a payout has actually been planned does the
    // ledger switch to the real figures — otherwise "you receive" would
    // twitch around as stock levels changed under a customer who has not
    // yet chosen anything, which reads as the machine changing its mind.
    final showBreakdown = step == KioskStep.selectOutput ||
        step == KioskStep.dispensing ||
        step == KioskStep.complete;

    final fee = showBreakdown ? controller.effectiveFee : controller.rawFee;
    final receives =
        showBreakdown ? controller.payableAmount : controller.grossPayout;

    return SizedBox(
      width: 268,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(controller.mode.title.isEmpty
                ? 'Your transaction'
                : controller.mode.title,
                style: AppText.bodyStrong),
            const SizedBox(height: AppSpace.lg),

            Text('You put in', style: AppText.caption),
            const SizedBox(height: AppSpace.xs),
            Text(peso(inserted), style: AppText.money),

            const SizedBox(height: AppSpace.lg),
            const Divider(color: AppColors.hairline, height: 1),
            const SizedBox(height: AppSpace.md),

            if (fee > 0) ...[
              _Line(label: 'Service fee', value: '−${peso(fee)}'),
              const SizedBox(height: AppSpace.sm),
            ],
            _Line(
              label: 'You receive',
              value: peso(receives),
              emphasise: true,
            ),

            if (showBreakdown && controller.proposedPlan.units.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text(
                controller.proposedPlan.describe(),
                style: AppText.caption.copyWith(height: 1.5),
              ),
            ],

            const Spacer(),

            if (controller.idleWarning) ...[
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.goldTint,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  inserted > 0
                      ? 'Still there? Your cash will be dispensed shortly.'
                      : 'Still there? This will reset shortly.',
                  style: AppText.caption.copyWith(color: AppColors.gold),
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],

            // No cancel once a hopper is running — there is nothing to
            // cancel to, and offering the button would imply otherwise.
            if (!step.isCommitted && step != KioskStep.complete)
              QuietButton(
                label: inserted > 0 ? 'Finish now' : 'Cancel',
                onPressed: controller.cancelTransaction,
                fullWidth: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;
  const _Line({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: emphasise ? AppText.bodyStrong : AppText.body,
        ),
        Text(
          value,
          style: emphasise
              ? AppText.moneySmall.copyWith(color: AppColors.green)
              : AppText.moneySmall.copyWith(
                  fontSize: 17,
                  color: AppColors.textSecondary,
                ),
        ),
      ],
    );
  }
}

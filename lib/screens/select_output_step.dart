import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/denomination.dart';
import '../state/change_planner.dart';
import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/custom_mix_sheet.dart';

class SelectOutputStep extends StatelessWidget {
  const SelectOutputStep({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KioskController>();

    // Read the cached plan — planning is pure and memoised on the
    // controller. The old build called the planner inside build(), and that
    // planner wrote a Firestore alert whenever stock was short, so every
    // rebuild of this screen fired another document write.
    final plan = controller.proposedPlan;
    final canConfirm = controller.canConfirmPayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How would you like it?', style: AppText.title),
        const SizedBox(height: AppSpace.xs),
        Text(
          controller.mode == ExchangeMode.pabarya
              ? 'We will give you the smallest pieces we can.'
              : 'We will give you the fewest notes we can.',
          style: AppText.body,
        ),

        if (controller.hasShortfall) ...[
          const SizedBox(height: AppSpace.md),
          _ShortfallWarning(shortfall: plan.shortfall),
        ],

        const SizedBox(height: AppSpace.lg),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _RecommendedCard(
                  plan: plan,
                  modeTitle: controller.mode == ExchangeMode.pabarya
                      ? 'Smallest pieces'
                      : 'Fewest notes',
                ),
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                flex: 2,
                child: _CustomCard(
                  enabled: controller.payableAmount > 0,
                  onTap: () => _openCustomMix(context, controller),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpace.lg),
        PrimaryButton(
          label: canConfirm
              ? 'Give me ${peso(controller.payableAmount)}'
              : 'Not available right now',
          icon: canConfirm ? Icons.arrow_forward : null,
          onPressed: canConfirm ? () => controller.confirmPayout(plan) : null,
          fullWidth: true,
        ),
      ],
    );
  }

  Future<void> _openCustomMix(
    BuildContext context,
    KioskController controller,
  ) async {
    final chosen = await showModalBottomSheet<DispensePlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.frame),
        ),
      ),
      builder: (_) => CustomMixSheet(
        payout: controller.payableAmount,
        stock: controller.firebase.stockSnapshot(),
      ),
    );

    if (chosen == null) return;
    // Guard the async gap: the customer could have been timed out, or the
    // hardware could have dropped, while the sheet was open.
    if (!context.mounted) return;
    await controller.confirmPayout(chosen);
  }
}

/// Disclosed *before* the customer commits, not filed as an alert they will
/// never see. The old behaviour dispensed the short amount anyway and logged
/// the gap to Firestore.
class _ShortfallWarning extends StatelessWidget {
  final int shortfall;
  const _ShortfallWarning({required this.shortfall});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.dangerTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          const Icon(Icons.report_outlined, size: 20, color: AppColors.danger),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'This kiosk is ${peso(shortfall)} short of your exact amount. '
              'Please ask the attendant before continuing.',
              style: AppText.bodyStrong.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final DispensePlan plan;
  final String modeTitle;
  const _RecommendedCard({required this.plan, required this.modeTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            modeTitle,
            style: AppText.bodyStrong.copyWith(color: AppColors.onInkMuted),
          ),
          const SizedBox(height: AppSpace.lg),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in _sorted(plan))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(
                              '${entry.value}×',
                              style: AppText.moneySmall
                                  .copyWith(color: AppColors.onInk),
                            ),
                          ),
                          Text(
                            entry.key.label,
                            style: AppText.body.copyWith(
                              color: AppColors.onInk,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (plan.units.isEmpty)
                    Text(
                      'Nothing can be dispensed at the moment.',
                      style: AppText.body.copyWith(color: AppColors.onInkMuted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<MapEntry<DispenseSlot, int>> _sorted(DispensePlan plan) {
    return plan.units.entries.toList()
      ..sort((a, b) => b.key.value.compareTo(a.key.value));
  }
}

class _CustomCard extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _CustomCard({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.panel),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.tune, size: 34, color: AppColors.gold),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pick it myself', style: AppText.heading),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Choose exactly which notes and coins you want.',
                    style: AppText.body,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

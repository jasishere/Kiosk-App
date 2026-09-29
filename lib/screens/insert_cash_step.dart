import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';

class InsertCashStep extends StatelessWidget {
  const InsertCashStep({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KioskController>();
    final amount = controller.amountInserted;
    final isPabarya = controller.mode == ExchangeMode.pabarya;
    final shortOfMinimum = isPabarya && amount > 0 && amount < 20;
    final canProceed = controller.meetsMinimum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Insert your cash', style: AppText.title),
        const SizedBox(height: AppSpace.xs),
        Text(
          controller.acceptsNotes
              ? 'Feed notes and coins one at a time. Take your time.'
              : 'Coins only right now — note checking is offline.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSpace.lg),

        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.panel),
              border: Border.all(color: AppColors.hairline),
            ),
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _SlotDiagram(acceptsNotes: controller.acceptsNotes),
                const SizedBox(height: AppSpace.lg),
                Text(
                  amount == 0
                      ? 'Waiting for your first coin or note'
                      : 'Keep going, or finish when you are ready',
                  style: AppText.body.copyWith(fontSize: 17),
                  textAlign: TextAlign.center,
                ),
                if (controller.notice != null) ...[
                  const SizedBox(height: AppSpace.lg),
                  _NoticeBanner(notice: controller.notice!),
                ],
                if (shortOfMinimum) ...[
                  const SizedBox(height: AppSpace.lg),
                  _NoticeBanner(
                    notice: InlineNotice(
                      'Add ${peso(20 - amount)} more — pabarya needs ₱20 to '
                      'make coin change worthwhile.',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpace.lg),
        PrimaryButton(
          label: canProceed
              ? 'Done — choose my cash'
              : 'Insert cash to continue',
          icon: canProceed ? Icons.arrow_forward : null,
          // Null, not an empty closure. A button that looks live and eats
          // the tap teaches people the screen is broken.
          onPressed: canProceed ? controller.doneInserting : null,
          fullWidth: true,
        ),
      ],
    );
  }
}

/// Shows which slot to use, with the note slot dimmed when the classifier is
/// down so the instruction always matches what the hardware will accept.
class _SlotDiagram extends StatelessWidget {
  final bool acceptsNotes;
  const _SlotDiagram({required this.acceptsNotes});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Slot(
          icon: Icons.payments_outlined,
          label: 'Note slot',
          enabled: acceptsNotes,
        ),
        const SizedBox(width: AppSpace.xxl),
        const _Slot(
          icon: Icons.savings_outlined,
          label: 'Coin slot',
          enabled: true,
        ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  const _Slot({required this.icon, required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.green : AppColors.textMuted;
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: enabled ? AppColors.greenTint : AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: Icon(icon, size: 44, color: color),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(label, style: AppText.caption.copyWith(color: color)),
        if (!enabled)
          Text('Unavailable',
              style: AppText.caption.copyWith(color: AppColors.danger)),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final InlineNotice notice;
  const _NoticeBanner({required this.notice});

  @override
  Widget build(BuildContext context) {
    final color = notice.isWarning ? AppColors.gold : AppColors.green;
    final background =
        notice.isWarning ? AppColors.goldTint : AppColors.greenTint;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notice.isWarning ? Icons.info_outline : Icons.check_circle_outline,
              size: 20,
              color: color,
            ),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(
                notice.message,
                style: AppText.bodyStrong.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

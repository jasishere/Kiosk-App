import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';

/// Live dispense progress.
///
/// Because the controller now waits for each hopper to acknowledge before
/// starting the next, this screen can show what has actually landed in the
/// tray rather than an indeterminate spinner that finishes when the first
/// hopper happens to report done.
class DispensingStep extends StatelessWidget {
  const DispensingStep({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KioskController>();
    final plan = controller.activePlan;
    final planned = plan?.pieceCount ?? 0;
    final done = controller.dispensedSoFar.values.fold<int>(0, (a, b) => a + b);
    final progress = planned == 0 ? null : (done / planned).clamp(0.0, 1.0);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Counting out your cash', style: AppText.title),
            const SizedBox(height: AppSpace.xs),
            Text('Please wait — collect it from the tray below.',
                style: AppText.body),
            const SizedBox(height: AppSpace.xl),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppColors.hairline,
                valueColor: const AlwaysStoppedAnimation(AppColors.green),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              planned == 0 ? 'Starting' : '$done of $planned pieces',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}

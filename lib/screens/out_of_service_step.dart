import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';

/// Standing refusal to take money.
///
/// Its own step rather than an error overlay, because no customer action can
/// clear it and the kiosk must not present a start button it cannot honour.
/// The wording tells the customer the one thing they need (their money is
/// safe, go elsewhere) and gives an attendant enough to act on.
class OutOfServiceStep extends StatelessWidget {
  const OutOfServiceStep({super.key});

  @override
  Widget build(BuildContext context) {
    final reason = context.select<KioskController, OutageReason>((c) => c.outage);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.panel),
              ),
              child: const Icon(Icons.build_outlined,
                  size: 44, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            Text('Temporarily out of service',
                style: AppText.title, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.sm),
            Text(
              'This kiosk is not accepting cash right now. '
              'Nothing has been taken from you.',
              style: AppText.body.copyWith(fontSize: 17),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.xl),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Text(_detail(reason), style: AppText.caption),
            ),
          ],
        ),
      ),
    );
  }

  String _detail(OutageReason reason) => switch (reason) {
        OutageReason.hardware => 'Reference: cash handling controller offline',
        OutageReason.classifier => 'Reference: note checking offline',
        OutageReason.stockUnknown => 'Reference: cash levels unavailable',
        OutageReason.none => 'Reference: starting up',
      };
}

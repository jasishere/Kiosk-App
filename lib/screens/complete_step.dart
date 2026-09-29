import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';

/// Closing summary — what was actually dispensed, not what was planned.
class CompleteStep extends StatefulWidget {
  const CompleteStep({super.key});

  @override
  State<CompleteStep> createState() => _CompleteStepState();
}

class _CompleteStepState extends State<CompleteStep> {
  Timer? _autoReturn;

  @override
  void initState() {
    super.initState();
    _autoReturn = Timer(AppConfig.completeAutoReturn, () {
      if (mounted) context.read<KioskController>().restart();
    });
  }

  @override
  void dispose() {
    _autoReturn?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KioskController>();
    final paid = controller.dispensedSoFar.entries
        .fold<int>(0, (sum, e) => sum + e.key.value * e.value);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, size: 56, color: AppColors.green),
            const SizedBox(height: AppSpace.md),
            Text('Take your cash', style: AppText.title),
            const SizedBox(height: AppSpace.xs),
            Text('${peso(paid)} is in the tray below.',
                style: AppText.body.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpace.lg),
            for (final entry in controller.dispensedSoFar.entries)
              if (entry.value > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: Text('${entry.value} × ${entry.key.label}',
                      style: AppText.body),
                ),
            const SizedBox(height: AppSpace.xl),
            PrimaryButton(
              label: 'Start another',
              onPressed: controller.restart,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/colors.dart';
import '../state/kiosk_controller.dart';
import '../widgets/buttons.dart';

/// How long the "transaction complete" screen waits for the customer to
/// start a new transaction before auto-returning to the welcome screen.
const _autoRestartDelay = Duration(seconds: 20);

class CompleteStep extends StatefulWidget {
  const CompleteStep({super.key});

  @override
  State<CompleteStep> createState() => _CompleteStepState();
}

class _CompleteStepState extends State<CompleteStep> {
  Timer? _autoRestartTimer;

  @override
  void initState() {
    super.initState();
    _autoRestartTimer = Timer(_autoRestartDelay, () {
      if (mounted) context.read<KioskController>().restart();
    });
  }

  @override
  void dispose() {
    _autoRestartTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KioskController>();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Transaction complete',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          uppercaseLabel('Take your cash and receipt'),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedGreenButton(
          label: uppercaseLabel('Start new transaction'),
          onPressed: controller.restart,
        ),
      ],
    );
  }
}

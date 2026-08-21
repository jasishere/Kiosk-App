import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/colors.dart';
import '../state/kiosk_controller.dart';
import '../widgets/buttons.dart';

/// Full-screen error overlay drawn on top of the kiosk frame whenever
/// KioskController.error is not KioskError.none. Covers hardware
/// disconnects, jams, AI service outages, and bill rejections — every
/// path in KioskController._fail() surfaces here.
class ErrorOverlay extends StatelessWidget {
  const ErrorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final err = context.select<KioskController, KioskError>((c) => c.error);
    if (err == KioskError.none) return const SizedBox.shrink();

    final detail =
        context.select<KioskController, String?>((c) => c.errorDetail);
    final controller = context.read<KioskController>();

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconFor(err), size: 40, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              _titleFor(err),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.mutedOnDark,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedGreenButton(
              label: uppercaseLabel(_actionLabelFor(err)),
              onPressed: () => controller.restart(),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(KioskError err) {
    switch (err) {
      case KioskError.hardwareOffline:
        return Icons.memory;
      case KioskError.aiOffline:
        return Icons.smart_toy_outlined;
      case KioskError.billRejected:
        return Icons.money_off;
      case KioskError.jam:
        return Icons.report_gmailerrorred;
      case KioskError.dispenseFailed:
        return Icons.warning_amber_rounded;
      case KioskError.none:
        return Icons.check;
    }
  }

  String _titleFor(KioskError err) {
    switch (err) {
      case KioskError.hardwareOffline:
        return 'Kiosk temporarily unavailable';
      case KioskError.aiOffline:
        return 'Authentication service unavailable';
      case KioskError.billRejected:
        return 'Bill could not be verified';
      case KioskError.jam:
        return 'Please wait — clearing a jam';
      case KioskError.dispenseFailed:
        return 'Dispensing error';
      case KioskError.none:
        return '';
    }
  }

  String _actionLabelFor(KioskError err) {
    switch (err) {
      case KioskError.billRejected:
        return 'Try again';
      default:
        return 'Start over';
    }
  }
}

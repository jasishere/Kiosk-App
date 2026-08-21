import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../widgets/buttons.dart';

class DispensingStep extends StatelessWidget {
  const DispensingStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 38,
          height: 38,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: AppColors.green,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Dispensing your cash',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          uppercaseLabel('Collect from the tray below'),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

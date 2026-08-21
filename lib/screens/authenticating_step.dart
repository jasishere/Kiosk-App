import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/colors.dart';
import '../state/kiosk_controller.dart';
import '../widgets/buttons.dart';

class AuthenticatingStep extends StatelessWidget {
  const AuthenticatingStep({super.key});

  @override
  Widget build(BuildContext context) {
    final aiOnline =
        context.select<KioskController, bool>((c) => c.aiServiceOnline);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.document_scanner_outlined, size: 38, color: AppColors.green),
        const SizedBox(height: 12),
        const Text(
          'Verifying banknote',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          uppercaseLabel(
            aiOnline ? 'AI authentication in progress' : 'Falling back to basic checks',
          ),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(
          width: 220,
          height: 3,
          child: LinearProgressIndicator(
            backgroundColor: AppColors.screenBorder,
            valueColor: AlwaysStoppedAnimation(AppColors.green),
          ),
        ),
      ],
    );
  }
}

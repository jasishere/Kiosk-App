import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/colors.dart';
import '../state/kiosk_controller.dart';
import '../widgets/buttons.dart';

class InsertCashStep extends StatelessWidget {
  const InsertCashStep({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KioskController>();
    final amount =
        context.select<KioskController, int>((c) => c.amountInsertedPesos);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Insert your cash',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          uppercaseLabel('Feed bills and coins one at a time'),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.greenTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.info_outline, size: 14, color: AppColors.green),
              SizedBox(width: 6),
              Text(
                'Accepts ₱20 and up only — no denominations below ₱20',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.screenBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(height: 4, color: AppColors.green),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.payments, size: 27, color: AppColors.green),
                            const SizedBox(height: 8),
                            Text(
                              uppercaseLabel(
                                amount == 0 ? 'Waiting for input' : 'Accepting more, or hit done',
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 180,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.screenBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uppercaseLabel('Amount inserted'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₱${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: AppColors.goldDark,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: PrimaryButton(
                          label: uppercaseLabel('Done inserting'),
                          onPressed: amount > 0 ? controller.doneInserting : () {},
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/colors.dart';
import '../state/kiosk_controller.dart';
import '../widgets/buttons.dart';

/// Standard PHP bill denominations the dispenser stocks, largest first.
/// ₱20 and up only, matching the kiosk's accepted-input floor.
const _kDenominations = [1000, 500, 200, 100, 50, 20];

/// Greedy denomination breakdown — simplest correct approach for a
/// kiosk dispenser with unlimited-looking stock. Swap for a
/// stock-aware algorithm once you wire in live inventory counts from
/// FirebaseService.watchInventory().
Map<int, int> _greedyBreakdown(int amount) {
  final result = <int, int>{};
  var remaining = amount;
  for (final denom in _kDenominations) {
    final count = remaining ~/ denom;
    if (count > 0) {
      result[denom] = count;
      remaining -= denom * count;
    }
  }
  return result;
}

class SelectOutputStep extends StatelessWidget {
  const SelectOutputStep({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KioskController>();
    final amount =
        context.select<KioskController, int>((c) => c.amountInsertedPesos);
    final quickMix = _greedyBreakdown(amount);
    final quickMixLabel = quickMix.entries
        .map((e) => '${e.value}x ₱${e.key}')
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '₱${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.goldDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          uppercaseLabel('Received — choose your output'),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => controller.confirmOutput(quickMix),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: -16,
                          left: -16,
                          right: -16,
                          child: Container(height: 4, color: AppColors.green),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Quick mix',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              quickMixLabel.isEmpty ? '—' : quickMixLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.mutedOnDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    // TODO: replace with a real denomination picker
                    // (bottom sheet or dedicated screen) that lets the
                    // user adjust counts per denomination, then calls
                    // controller.confirmOutput(customBreakdown).
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Custom mix picker not built yet — use Quick mix'),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.screenBorder),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: -16,
                          left: -16,
                          right: -16,
                          child: Container(height: 4, color: AppColors.goldDark),
                        ),
                        const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Custom mix',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Choose your own combination',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: PrimaryButton(
            label: uppercaseLabel('Confirm quick mix'),
            onPressed: () => controller.confirmOutput(quickMix),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

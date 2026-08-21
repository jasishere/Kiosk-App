import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/colors.dart';
import '../state/kiosk_controller.dart';
import '../widgets/buttons.dart';

class ModeSelectStep extends StatelessWidget {
  const ModeSelectStep({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KioskController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What would you like to do?',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          uppercaseLabel('Select an exchange mode'),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _ModeCard(
                  icon: Icons.paid_outlined,
                  iconColor: AppColors.green,
                  iconBg: AppColors.greenTint,
                  topBorderColor: AppColors.green,
                  title: 'Pabarya',
                  description: 'Break a bill into coins and smaller cash',
                  footnote: '₱20 and up only',
                  footnoteColor: AppColors.green,
                  onTap: () => controller.selectMode(ExchangeMode.pabarya),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  icon: Icons.payments_outlined,
                  iconColor: AppColors.goldDark,
                  iconBg: AppColors.goldTint,
                  topBorderColor: AppColors.goldDark,
                  title: 'Pabuo',
                  description: 'Combine coins and bills into a bigger bill',
                  footnote: 'Any mix accepted',
                  footnoteColor: AppColors.goldDark,
                  onTap: () => controller.selectMode(ExchangeMode.pabuo),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color topBorderColor;
  final String title;
  final String description;
  final String footnote;
  final Color footnoteColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.topBorderColor,
    required this.title,
    required this.description,
    required this.footnote,
    required this.footnoteColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.screenBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -18,
                left: -18,
                right: -18,
                child: Container(height: 4, color: topBorderColor),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, size: 18, color: iconColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    footnote,
                    style: TextStyle(
                      fontSize: 12,
                      color: footnoteColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

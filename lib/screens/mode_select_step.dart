import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/kiosk_controller.dart';
import '../theme/app_theme.dart';

class ModeSelectStep extends StatelessWidget {
  const ModeSelectStep({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KioskController>();
    final acceptsNotes =
        context.select<KioskController, bool>((c) => c.acceptsNotes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What do you need?', style: AppText.title),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Pick one to begin. You can put in coins and notes together.',
          style: AppText.body,
        ),
        if (!acceptsNotes) ...[
          const SizedBox(height: AppSpace.md),
          const _CoinsOnlyBanner(),
        ],
        const SizedBox(height: AppSpace.lg),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ModeCard(
                  icon: Icons.call_split,
                  accent: AppColors.green,
                  tint: AppColors.greenTint,
                  title: 'Pabarya',
                  subtitle: 'Break your cash into coins and smaller notes',
                  note: 'Needs at least ₱20',
                  onTap: () => controller.selectMode(ExchangeMode.pabarya),
                ),
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: _ModeCard(
                  icon: Icons.call_merge,
                  accent: AppColors.gold,
                  tint: AppColors.goldTint,
                  title: 'Pabuo',
                  subtitle: 'Turn coins and small notes into bigger notes',
                  note: 'Any amount',
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

class _CoinsOnlyBanner extends StatelessWidget {
  const _CoinsOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.goldTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.gold),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Note checking is offline, so the kiosk is taking coins only '
              'right now. You can still be paid out in notes.',
              style: AppText.caption.copyWith(color: AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  final IconData icon;
  final Color accent;
  final Color tint;
  final String title;
  final String subtitle;
  final String note;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.accent,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.note,
    required this.onTap,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.hairline),
              borderRadius: BorderRadius.circular(AppRadius.panel),
            ),
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: widget.tint,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(widget.icon, size: 34, color: widget.accent),
                ),
                const Spacer(),
                Text(
                  widget.title,
                  style: AppText.title.copyWith(fontSize: 34),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  widget.subtitle,
                  style: AppText.body.copyWith(fontSize: 17),
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  widget.note,
                  style: AppText.caption.copyWith(
                    color: widget.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

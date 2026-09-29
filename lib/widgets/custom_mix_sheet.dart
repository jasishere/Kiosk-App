import 'package:flutter/material.dart';

import '../models/denomination.dart';
import '../state/change_planner.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';

/// Lets the customer build their own payout.
///
/// Every stepper is hard-capped at true availability, and the confirm button
/// only unlocks when the counts sum to the payout exactly — so a hand-built
/// mix can never promise cash the kiosk does not hold, and can never come
/// out short.
///
/// Note what is deliberately *not* on screen: exact hopper counts. A public
/// panel that advertises "17 × ₱1000 remaining" tells the wrong person
/// exactly what is inside the cabinet. The stepper simply stops, with a
/// plain-language reason.
class CustomMixSheet extends StatefulWidget {
  final int payout;
  final Map<DispenseSlot, int> stock;

  const CustomMixSheet({
    super.key,
    required this.payout,
    required this.stock,
  });

  @override
  State<CustomMixSheet> createState() => _CustomMixSheetState();
}

class _CustomMixSheetState extends State<CustomMixSheet> {
  final Map<DispenseSlot, int> _chosen = {};

  int get _total => _chosen.entries
      .fold(0, (sum, e) => sum + e.key.value * e.value);

  int get _remaining => widget.payout - _total;

  int _available(DispenseSlot slot) => widget.stock[slot] ?? 0;

  int _count(DispenseSlot slot) => _chosen[slot] ?? 0;

  bool _canAdd(DispenseSlot slot) =>
      _count(slot) < _available(slot) && slot.value <= _remaining;

  void _adjust(DispenseSlot slot, int delta) {
    final next = _count(slot) + delta;
    if (next < 0) return;
    if (delta > 0 && !_canAdd(slot)) return;
    setState(() {
      if (next == 0) {
        _chosen.remove(slot);
      } else {
        _chosen[slot] = next;
      }
    });
  }

  /// Fills the remaining balance using the planner, so a customer who picks
  /// a couple of specific notes isn't forced to tap out the rest by hand.
  void _fillRest() {
    if (_remaining <= 0) return;
    final residualStock = <DispenseSlot, int>{
      for (final entry in widget.stock.entries)
        entry.key: entry.value - _count(entry.key),
    };
    final plan = ChangePlanner.plan(
      amount: _remaining,
      stock: residualStock,
      preference: MixPreference.consolidate,
    );
    if (!plan.isExact) return;
    setState(() {
      plan.units.forEach((slot, count) {
        _chosen[slot] = _count(slot) + count;
      });
    });
  }

  bool get _canConfirm => _remaining == 0 && _total > 0;

  @override
  Widget build(BuildContext context) {
    // Only slots that could actually take part: in stock, and no larger than
    // the payout itself.
    final usable = kDispenseSlots
        .where((s) => _available(s) > 0 && s.value <= widget.payout)
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pick your cash', style: AppText.heading),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        _remaining == 0
                            ? 'That adds up. Ready when you are.'
                            : '${peso(_remaining)} still to choose',
                        style: AppText.body.copyWith(
                          color: _remaining == 0
                              ? AppColors.green
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(peso(widget.payout), style: AppText.money),
              ],
            ),
            const SizedBox(height: AppSpace.lg),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final slot in usable)
                      _SlotRow(
                        slot: slot,
                        count: _count(slot),
                        atStockCap: _count(slot) >= _available(slot),
                        canAdd: _canAdd(slot),
                        onAdd: () => _adjust(slot, 1),
                        onRemove:
                            _count(slot) > 0 ? () => _adjust(slot, -1) : null,
                      ),
                    if (usable.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        child: Text(
                          'No denominations are available to choose from.',
                          style: AppText.body,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: QuietButton(
                    label: 'Fill the rest for me',
                    onPressed: _remaining > 0 ? _fillRest : null,
                    fullWidth: true,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    label: _canConfirm
                        ? 'Give me this'
                        : '${peso(_remaining)} still to choose',
                    onPressed: _canConfirm
                        ? () => Navigator.of(context).pop(
                              DispensePlan(
                                units: Map.of(_chosen),
                                dispensed: _total,
                                shortfall: 0,
                              ),
                            )
                        : null,
                    fullWidth: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  final DispenseSlot slot;
  final int count;
  final bool atStockCap;
  final bool canAdd;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;

  const _SlotRow({
    required this.slot,
    required this.count,
    required this.atStockCap,
    required this.canAdd,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: slot.isBill ? AppColors.greenTint : AppColors.goldTint,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Icon(
              slot.isBill ? Icons.payments_outlined : Icons.circle_outlined,
              size: 24,
              color: slot.isBill ? AppColors.green : AppColors.gold,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.label, style: AppText.bodyStrong.copyWith(fontSize: 17)),
                if (atStockCap)
                  Text(
                    "That's all we have of these",
                    style: AppText.caption.copyWith(color: AppColors.gold),
                  ),
              ],
            ),
          ),
          StepperButton(icon: Icons.remove, onPressed: onRemove),
          SizedBox(
            width: 52,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: AppText.moneySmall,
            ),
          ),
          StepperButton(icon: Icons.add, onPressed: canAdd ? onAdd : null),
        ],
      ),
    );
  }
}

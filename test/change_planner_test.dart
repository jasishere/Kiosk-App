import 'dart:math';

import 'package:coinvert_kiosk/models/denomination.dart';
import 'package:coinvert_kiosk/state/change_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exhaustive reference: the largest value at or below [amount] that can be
/// assembled from [stock]. Slow, but it is ground truth.
int bruteBest(int amount, Map<DispenseSlot, int> stock) {
  var reachable = <int>{0};
  for (final entry in stock.entries) {
    final next = <int>{};
    for (final base in reachable) {
      for (var c = 0; c <= entry.value; c++) {
        final t = base + entry.key.value * c;
        if (t <= amount) next.add(t);
      }
    }
    reachable = next;
  }
  return reachable.reduce(max);
}

Map<DispenseSlot, int> stockOf(Map<String, int> byId) => {
      for (final slot in kDispenseSlots) slot: byId[slot.id] ?? 0,
    };

void main() {
  group('ChangePlanner', () {
    test('pays an ordinary amount exactly', () {
      final plan = ChangePlanner.plan(
        amount: 370,
        stock: stockOf({
          'bill-100': 5,
          'bill-50': 5,
          'bill-20': 5,
          'coin-10': 5,
          'coin-5': 5,
          'coin-1': 5,
        }),
      );
      expect(plan.isExact, isTrue);
      expect(plan.dispensed, 370);
    });

    test('never exceeds available stock', () {
      final stock = stockOf({'bill-100': 1, 'bill-50': 1, 'coin-10': 2});
      final plan = ChangePlanner.plan(amount: 170, stock: stock);
      plan.units.forEach((slot, count) {
        expect(count, lessThanOrEqualTo(stock[slot]!));
      });
      expect(plan.dispensed, 170);
    });

    test('solves the case greedy largest-first gets wrong', () {
      // One ₱50 and three ₱20. Greedy takes the ₱50, then cannot make the
      // remaining ₱10 and reports a shortfall. 3 × ₱20 pays it exactly.
      final plan = ChangePlanner.plan(
        amount: 60,
        stock: stockOf({'bill-50': 1, 'bill-20': 3}),
      );
      expect(plan.isExact, isTrue);
      expect(plan.dispensed, 60);
      expect(plan.pieceCount, 3);
    });

    test('reports a shortfall instead of quietly underpaying', () {
      final plan = ChangePlanner.plan(
        amount: 75,
        stock: stockOf({'bill-50': 1, 'bill-20': 1}),
      );
      expect(plan.isExact, isFalse);
      expect(plan.dispensed, 70);
      expect(plan.shortfall, 5);
    });

    test('returns a full shortfall when nothing is in stock', () {
      final plan = ChangePlanner.plan(amount: 100, stock: stockOf({}));
      expect(plan.units, isEmpty);
      expect(plan.shortfall, 100);
    });

    test('consolidate uses fewer pieces than breakDown', () {
      final stock = stockOf({
        'bill-500': 5,
        'bill-100': 5,
        'bill-50': 5,
        'bill-20': 5,
        'coin-20': 5,
        'coin-10': 5,
        'coin-5': 5,
        'coin-1': 5,
      });
      final fewest = ChangePlanner.plan(
        amount: 500,
        stock: stock,
        preference: MixPreference.consolidate,
      );
      final most = ChangePlanner.plan(
        amount: 500,
        stock: stock,
        preference: MixPreference.breakDown,
      );
      expect(fewest.dispensed, 500);
      expect(most.dispensed, 500);
      expect(fewest.pieceCount, lessThan(most.pieceCount));
    });

    test('keeps the two ₱20 slots separate', () {
      // A ₱20 note and a ₱20 coin live in different hoppers. Planning must
      // not spend coin stock as if it were note stock.
      final plan = ChangePlanner.plan(
        amount: 40,
        stock: stockOf({'bill-20': 1, 'coin-20': 1}),
      );
      expect(plan.dispensed, 40);
      expect(plan.units.length, 2);
    });

    test('rejects amounts beyond the per-transaction ceiling', () {
      final plan = ChangePlanner.plan(
        amount: ChangePlanner.maxPayout + 1,
        stock: stockOf({'bill-1000': 100}),
      );
      expect(plan.isExact, isFalse);
      expect(plan.units, isEmpty);
    });

    test('matches an exhaustive solver across randomised stock', () {
      final rng = Random(11);
      const limits = [0, 0, 1, 2, 3, 5, 10];

      for (var trial = 0; trial < 400; trial++) {
        final stock = <DispenseSlot, int>{
          for (final slot in kDispenseSlots)
            slot: limits[rng.nextInt(limits.length)],
        };
        final amount = 1 + rng.nextInt(600);
        final preference = rng.nextBool()
            ? MixPreference.breakDown
            : MixPreference.consolidate;

        final plan = ChangePlanner.plan(
          amount: amount,
          stock: stock,
          preference: preference,
        );

        final summed = plan.units.entries
            .fold<int>(0, (sum, e) => sum + e.key.value * e.value);
        expect(summed, plan.dispensed, reason: 'plan does not sum to itself');
        expect(plan.dispensed + plan.shortfall, amount);

        plan.units.forEach((slot, count) {
          expect(count, lessThanOrEqualTo(stock[slot]!),
              reason: 'over stock on ${slot.id}');
        });

        expect(plan.dispensed, bruteBest(amount, stock),
            reason: 'suboptimal for $amount');
      }
    });
  });
}

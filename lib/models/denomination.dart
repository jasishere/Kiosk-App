/// A physical output channel the kiosk can dispense from.
///
/// This is deliberately NOT "any integer >= 20 is a bill". The ₱20 exists in
/// circulation as both a coin and a banknote, and they live in different
/// hoppers with different stock counts — treating them as one denomination
/// meant the kiosk could promise ₱20 notes out of the coin hopper's stock.
/// Each slot is its own entity with its own inventory key.
class DispenseSlot {
  /// Face value in whole pesos.
  final int value;

  /// True if this slot holds banknotes (dispensed by the note module),
  /// false if it holds coins (dispensed by a coin hopper).
  final bool isBill;

  const DispenseSlot(this.value, {required this.isBill});

  /// Firestore field key — matches the admin app's
  /// `inventory/current.bills{}` / `.coins{}` maps.
  String get inventoryKey => value.toString();

  /// Stable identity for maps and equality.
  String get id => '${isBill ? 'bill' : 'coin'}-$value';

  String get label => '₱$value ${isBill ? 'bill' : 'coin'}';

  @override
  bool operator ==(Object other) => other is DispenseSlot && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

/// Every channel this kiosk is physically built to dispense from.
///
/// Trim this list to match the hardware you actually install — a slot listed
/// here that has no hopper behind it will be planned into breakdowns and
/// then time out at dispense time. Ordered largest→smallest purely for
/// readability; the change planner sorts it itself.
const List<DispenseSlot> kDispenseSlots = [
  DispenseSlot(1000, isBill: true),
  DispenseSlot(500, isBill: true),
  DispenseSlot(200, isBill: true),
  DispenseSlot(100, isBill: true),
  DispenseSlot(50, isBill: true),
  DispenseSlot(20, isBill: true),
  DispenseSlot(20, isBill: false),
  DispenseSlot(10, isBill: false),
  DispenseSlot(5, isBill: false),
  DispenseSlot(1, isBill: false),
];

/// The smallest unit the kiosk can hand back. Any payout must be a whole
/// multiple of this or it is not representable — used to keep fee rounding
/// honest rather than producing an amount no hopper combination can make.
const int kSmallestUnit = 1;

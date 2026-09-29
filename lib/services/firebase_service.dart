import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../models/denomination.dart';

// ─── SCHEMA ───────────────────────────────────────────────────────────────
// Matches the collections the Coinvert admin app already reads. Do not
// rename fields here without changing the admin side in the same commit.
//
//   transactions/{autoId}
//     kioskId, timestamp, status, type, input.totalValue, feeCharged,
//     output.totalValue, output.breakdown
//
//   flaggedBills/{autoId}
//     kioskId, denomination, timestamp,
//     aiPrediction: { confidence, denomination, kioskId, timestamp },
//     adminReview:  { status, reviewedBy, reviewedAt, notes }
//
//   kiosks/{kioskId}                     name, location, ownerId, status,
//                                        feeEnabled, feePercent, updatedAt
//   kiosks/{kioskId}/inventory/current   bills{denom:qty}, coins{denom:qty},
//                                        disabledBills{}, disabledCoins{}
//   kiosks/{kioskId}/alerts/{autoId}     type, title, message, read, timestamp
//
// AUTH: every write requires request.auth != null. The kiosk has no login,
// so it signs in anonymously at startup. Enable the Anonymous provider in
// the Firebase console or every write below fails.
// ──────────────────────────────────────────────────────────────────────────

/// Input→output pair, using the four labels the admin app renders.
enum TxType { billCoin, coinBill, coinCoin, billBill }

extension TxTypeWire on TxType {
  String get wireValue => switch (this) {
        TxType.billCoin => 'bill-coin',
        TxType.coinBill => 'coin-bill',
        TxType.coinCoin => 'coin-coin',
        TxType.billBill => 'bill-bill',
      };
}

class TransactionRecord {
  final String kioskId;
  final TxType type;
  final double totalValue;
  final String status; // completed | cancelled | refunded | error
  final double feeCharged;
  final double payoutValue;
  final Map<String, int> breakdown; // slot id → units actually dispensed

  const TransactionRecord({
    required this.kioskId,
    required this.type,
    required this.totalValue,
    required this.status,
    this.feeCharged = 0,
    this.payoutValue = 0,
    this.breakdown = const {},
  });

  Map<String, dynamic> toJson() => {
        'kioskId': kioskId,
        'type': type.wireValue,
        'status': status,
        'input': {'totalValue': totalValue},
        'output': {'totalValue': payoutValue, 'breakdown': breakdown},
        'feeCharged': feeCharged,
        'timestamp': FieldValue.serverTimestamp(),
      };
}

class FlaggedBillRecord {
  final String kioskId;
  final int denomination;
  final double confidence;

  const FlaggedBillRecord({
    required this.kioskId,
    required this.denomination,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'kioskId': kioskId,
        'denomination': denomination,
        'timestamp': FieldValue.serverTimestamp(),
        'aiPrediction': {
          'confidence': confidence,
          'denomination': denomination,
          'kioskId': kioskId,
          'timestamp': FieldValue.serverTimestamp(),
        },
        'adminReview': {
          'status': 'pending',
          'reviewedBy': '',
          'reviewedAt': null,
          'notes': '',
        },
      };
}

class KioskErrorRecord {
  final String code;
  final String message;
  const KioskErrorRecord({required this.code, required this.message});
}

/// Firestore + Auth wrapper for the kiosk.
///
/// Every write is failure-tolerant by design: a Firestore hiccup must never
/// interrupt a transaction that is already handling physical cash. Logging
/// is an observability concern, not a control-flow one.
class FirebaseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final String kioskId;

  FirebaseService({
    required this.kioskId,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('transactions');
  CollectionReference<Map<String, dynamic>> get _flaggedBills =>
      _firestore.collection('flaggedBills');
  DocumentReference<Map<String, dynamic>> get _kioskDoc =>
      _firestore.collection('kiosks').doc(kioskId);
  DocumentReference<Map<String, dynamic>> get _inventoryDoc =>
      _kioskDoc.collection('inventory').doc('current');
  CollectionReference<Map<String, dynamic>> get _alerts =>
      _kioskDoc.collection('alerts');

  // ── Live state ────────────────────────────────────────────────────────
  final Map<String, int> _bills = {};
  final Map<String, int> _coins = {};
  final Map<String, bool> _disabledBills = {};
  final Map<String, bool> _disabledCoins = {};

  bool _inventoryLoaded = false;
  bool _feeEnabled = false;
  double _feePercent = 0;
  int _lowStockThreshold = 20;

  bool get inventoryLoaded => _inventoryLoaded;
  bool get feeEnabled => _feeEnabled;
  double get feePercent => _feePercent;
  int get lowStockThreshold => _lowStockThreshold;

  final _lastLoggedError = <String, DateTime>{};

  Future<void> ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  /// Live fee + threshold config from the kiosk document.
  Stream<Map<String, dynamic>?> watchKioskConfig() {
    return _kioskDoc.snapshots().map((doc) {
      final data = doc.data();
      _feeEnabled = data?['feeEnabled'] as bool? ?? false;
      _feePercent = (data?['feePercent'] as num?)?.toDouble() ?? 0;
      _lowStockThreshold = (data?['lowStockThreshold'] as num?)?.toInt() ?? 20;
      return data;
    });
  }

  /// Live inventory. Keeps a local cache so the change planner can run
  /// synchronously without a read per denomination.
  Stream<Map<String, dynamic>?> watchInventory() {
    return _inventoryDoc.snapshots().map((doc) {
      final data = doc.data();
      if (data != null) {
        _readInto(_bills, data['bills']);
        _readInto(_coins, data['coins']);
        _readFlags(_disabledBills, data['disabledBills']);
        _readFlags(_disabledCoins, data['disabledCoins']);
        _inventoryLoaded = true;
      }
      return data;
    });
  }

  void _readInto(Map<String, int> target, Object? raw) {
    target.clear();
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) target[k.toString()] = v.toInt();
      });
    }
  }

  void _readFlags(Map<String, bool> target, Object? raw) {
    target.clear();
    if (raw is Map) {
      raw.forEach((k, v) => target[k.toString()] = v == true);
    }
  }

  /// Units of [slot] the kiosk can dispense right now.
  ///
  /// Returns 0 when inventory has not loaded yet. This is a deliberate
  /// reversal of the previous behaviour, which returned a 999999 sentinel so
  /// an unprovisioned kiosk "wouldn't be blocked" — but that meant a kiosk
  /// that had simply lost its Firestore connection would happily plan a
  /// payout of notes it did not hold, take the customer's money, and then
  /// fail at the hopper. Refusing to start until stock is known is the only
  /// safe default for a machine holding cash.
  int availableUnits(DispenseSlot slot) {
    if (!_inventoryLoaded) return 0;
    final disabled = slot.isBill ? _disabledBills : _disabledCoins;
    if (disabled[slot.inventoryKey] == true) return 0;
    final stock = slot.isBill ? _bills : _coins;
    return stock[slot.inventoryKey] ?? 0;
  }

  /// Snapshot of every slot's availability, for the change planner.
  Map<DispenseSlot, int> stockSnapshot() => {
        for (final slot in kDispenseSlots) slot: availableUnits(slot),
      };

  Future<void> logTransaction(TransactionRecord record) async {
    try {
      await _transactions.add(record.toJson());
    } catch (e) {
      debugPrint('[firestore] logTransaction failed: $e');
    }
  }

  Future<void> flagBill(FlaggedBillRecord record) async {
    try {
      await _flaggedBills.add(record.toJson());
    } catch (e) {
      debugPrint('[firestore] flagBill failed: $e');
    }
  }

  /// Writes a system alert, throttled per error code.
  ///
  /// Without the cooldown a stuck sensor firing every serial frame would
  /// write alert documents continuously — the sort of thing that is
  /// invisible in testing and turns into a five-figure document count and an
  /// unusable Alerts screen after one bad night in the field.
  Future<void> logError(KioskErrorRecord record) async {
    final last = _lastLoggedError[record.code];
    final now = DateTime.now();
    if (last != null && now.difference(last) < AppConfig.errorLogCooldown) {
      return;
    }
    _lastLoggedError[record.code] = now;

    try {
      await _alerts.add({
        'type': 'system',
        'code': record.code,
        'title': 'Kiosk error: ${record.code}',
        'message': record.message,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[firestore] logError failed: $e');
    }
  }

  /// Decrements inventory for a completed dispense and raises a low-stock
  /// alert if the slot has fallen to the threshold.
  ///
  /// One atomic `increment` per slot, not one write per unit. The previous
  /// implementation looped `await _inventoryDoc.update(...)` once per coin,
  /// so a 40-coin payout meant 40 sequential round-trips — several seconds
  /// of writes, and a non-atomic decrement that would drift permanently out
  /// of true if the app was killed partway through.
  Future<void> recordDispense(Map<DispenseSlot, int> dispensed) async {
    // Nested maps, not dotted paths. `update()` interprets "bills.20" as a
    // path, but `set(..., merge: true)` treats it as a literal field name
    // containing a dot — which would quietly create a junk top-level field
    // and leave real inventory untouched. A merged nested map does the
    // right thing and also creates the document if it does not exist yet.
    final bills = <String, Object>{};
    final coins = <String, Object>{};

    dispensed.forEach((slot, count) {
      if (count <= 0) return;
      final target = slot.isBill ? bills : coins;
      target[slot.inventoryKey] = FieldValue.increment(-count);
    });
    if (bills.isEmpty && coins.isEmpty) return;

    final updates = <String, Object>{
      if (bills.isNotEmpty) 'bills': bills,
      if (coins.isNotEmpty) 'coins': coins,
    };

    try {
      await _inventoryDoc.set(updates, SetOptions(merge: true));

      // Update the local cache so a payout begun before the snapshot round
      // trips back doesn't over-promise the same units twice.
      dispensed.forEach((slot, count) {
        final cache = slot.isBill ? _bills : _coins;
        final next = (cache[slot.inventoryKey] ?? 0) - count;
        cache[slot.inventoryKey] = next < 0 ? 0 : next;
      });

      await _raiseLowStockAlerts(dispensed.keys);
    } catch (e) {
      debugPrint('[firestore] recordDispense failed: $e');
    }
  }

  Future<void> _raiseLowStockAlerts(Iterable<DispenseSlot> slots) async {
    for (final slot in slots) {
      final remaining = availableUnits(slot);
      if (remaining > _lowStockThreshold) continue;

      try {
        final existing = await _alerts
            .where('type', isEqualTo: 'inventory')
            .where('slotId', isEqualTo: slot.id)
            .where('read', isEqualTo: false)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) continue;

        await _alerts.add({
          'type': 'inventory',
          'title': 'Low stock: ${slot.label}',
          'message': '$remaining left (alert threshold $_lowStockThreshold)',
          'slotId': slot.id,
          'denomination': slot.inventoryKey,
          'isBill': slot.isBill,
          'qty': remaining,
          'read': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[firestore] low stock alert failed: $e');
      }
    }
  }

  /// Heartbeat so the admin app can tell a healthy kiosk from one that has
  /// silently dropped off the network.
  Future<void> reportStatus({required String status}) async {
    try {
      await _kioskDoc.set({
        'status': status,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[firestore] reportStatus failed: $e');
    }
  }
}

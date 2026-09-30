import 'dart:async';

import 'package:firedart/firedart.dart';
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

/// firedart has no FieldValue.serverTimestamp(), so timestamps are the Pi's
/// clock in UTC. A Raspberry Pi has NO battery-backed RTC: make sure NTP is
/// working (`timedatectl status`) or these will be wrong after an offline boot.
DateTime _now() => DateTime.now().toUtc();

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
        'timestamp': _now(),
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
        'timestamp': _now(),
        'aiPrediction': {
          'confidence': confidence,
          'denomination': denomination,
          'kioskId': kioskId,
          'timestamp': _now(),
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

/// Firestore + Auth wrapper for the kiosk (firedart, pure Dart — works on
/// Linux/Raspberry Pi).
///
/// Every write is failure-tolerant by design: a Firestore hiccup must never
/// interrupt a transaction that is already handling physical cash. Logging
/// is an observability concern, not a control-flow one.
class FirebaseService {
  final String kioskId;

  FirebaseService({required this.kioskId});

  static bool _initialized = false;

  /// Call once, inside a try/catch, before anything else touches Firestore.
  static void initialize() {
    if (_initialized) return;
    FirebaseAuth.initialize(AppConfig.firebaseApiKey, VolatileStore());
    Firestore.initialize(AppConfig.firebaseProjectId);
    _initialized = true;
  }

  Firestore get _db => Firestore.instance;

  CollectionReference get _transactions => _db.collection('transactions');
  CollectionReference get _flaggedBills => _db.collection('flaggedBills');
  DocumentReference get _kioskDoc => _db.document('kiosks/$kioskId');
  DocumentReference get _inventoryDoc =>
      _db.document('kiosks/$kioskId/inventory/current');
  CollectionReference get _alerts => _db.collection('kiosks/$kioskId/alerts');

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
    final auth = FirebaseAuth.instance;
    if (!auth.isSignedIn) {
      await auth.signInAnonymously();
    }
  }

  /// Live fee + threshold config from the kiosk document.
  Stream<Map<String, dynamic>?> watchKioskConfig() {
    return _resilient(() => _kioskDoc.stream).map((doc) {
      final data = doc?.map;
      _feeEnabled = data?['feeEnabled'] as bool? ?? false;
      _feePercent = (data?['feePercent'] as num?)?.toDouble() ?? 0;
      _lowStockThreshold = (data?['lowStockThreshold'] as num?)?.toInt() ?? 20;
      return data;
    });
  }

  /// Live inventory. Keeps a local cache so the change planner can run
  /// synchronously without a read per denomination.
  Stream<Map<String, dynamic>?> watchInventory() {
    return _resilient(() => _inventoryDoc.stream).map((doc) {
      final data = doc?.map;
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

  /// firedart's listen streams can terminate on a network drop. A kiosk must
  /// recover on its own, so re-open the stream with a short backoff.
  Stream<T> _resilient<T>(Stream<T> Function() open) {
    late final StreamController<T> out;
    StreamSubscription<T>? sub;
    Timer? retry;
    var cancelled = false;

    void connect() {
      if (cancelled) return;
      void scheduleRetry() {
        if (cancelled) return;
        retry?.cancel();
        retry = Timer(AppConfig.reconnectInterval, connect);
      }

      try {
        sub = open().listen(
          out.add,
          onError: (Object e, StackTrace st) {
            out.addError(e, st);
            scheduleRetry();
          },
          onDone: scheduleRetry,
          cancelOnError: true,
        );
      } catch (e, st) {
        out.addError(e, st);
        scheduleRetry();
      }
    }

    out = StreamController<T>(
      onListen: connect,
      onCancel: () async {
        cancelled = true;
        retry?.cancel();
        await sub?.cancel();
      },
    );
    return out.stream;
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
        'timestamp': _now(),
      });
    } catch (e) {
      debugPrint('[firestore] logError failed: $e');
    }
  }

  Future<void> _dispenseLock = Future<void>.value();

  /// Decrements inventory for a completed dispense and raises a low-stock
  /// alert if the slot has fallen to the threshold.
  ///
  /// firedart has no atomic `FieldValue.increment`, so this is a
  /// read-modify-write: fetch the current server counts, subtract, write the
  /// `bills`/`coins` maps back. Calls are serialised so two payouts on this
  /// kiosk can't interleave. The remaining (tiny) race is an admin restock
  /// landing in the few milliseconds between our read and write.
  Future<void> recordDispense(Map<DispenseSlot, int> dispensed) {
    final run = _dispenseLock.then((_) => _recordDispense(dispensed));
    _dispenseLock = run.catchError((Object _) {});
    return run;
  }

  Future<void> _recordDispense(Map<DispenseSlot, int> dispensed) async {
    if (dispensed.values.every((c) => c <= 0)) return;

    try {
      final snap =
          await _inventoryDoc.exists ? await _inventoryDoc.get() : null;
      final current = snap?.map ?? const <String, dynamic>{};

      final bills = <String, int>{};
      final coins = <String, int>{};
      _readInto(bills, current['bills']);
      _readInto(coins, current['coins']);

      dispensed.forEach((slot, count) {
        if (count <= 0) return;
        final target = slot.isBill ? bills : coins;
        target[slot.inventoryKey] = (target[slot.inventoryKey] ?? 0) - count;
      });

      final updates = <String, dynamic>{'bills': bills, 'coins': coins};
      if (snap == null) {
        await _inventoryDoc.set(updates);
      } else {
        await _inventoryDoc.update(updates);
      }

      // Update the local cache so a payout begun before the snapshot round
      // trips back doesn't over-promise the same units twice.
      dispensed.forEach((slot, count) {
        if (count <= 0) return;
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
        if (existing.isNotEmpty) continue;

        await _alerts.add({
          'type': 'inventory',
          'title': 'Low stock: ${slot.label}',
          'message': '$remaining left (alert threshold $_lowStockThreshold)',
          'slotId': slot.id,
          'denomination': slot.inventoryKey,
          'isBill': slot.isBill,
          'qty': remaining,
          'read': false,
          'timestamp': _now(),
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
      final fields = {'status': status, 'lastSeenAt': _now()};
      // Never `set` over an existing kiosk doc: firedart's set() replaces the
      // whole document and would wipe name/location/ownerId.
      if (await _kioskDoc.exists) {
        await _kioskDoc.update(fields);
      } else {
        await _kioskDoc.set(fields);
      }
    } catch (e) {
      debugPrint('[firestore] reportStatus failed: $e');
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

// ─── SCHEMA NOTE ──────────────────────────────────────────────────────────
// This file was rewritten to match the REAL schema already used by the
// Coinvert admin app (lib/services/firestore_service.dart on that side),
// not a schema invented for the kiosk. Collections/fields below are taken
// directly from the admin app's Firestore rules and reads:
//
//   transactions/{autoId}            (top-level)
//     kioskId, timestamp, status, type, input.totalValue
//
//   flaggedBills/{autoId}            (top-level)
//     kioskId, denomination, timestamp,
//     aiPrediction: { confidence, denomination, kioskId, timestamp },
//     adminReview:  { status: 'pending'|'approved'|'rejected',
//                      reviewedBy, reviewedAt, notes }
//
//   kiosks/{kioskId}                 name, location, ownerId, status, updatedAt
//   kiosks/{kioskId}/inventory/current   bills{denom:qty}, coins{denom:qty}
//   kiosks/{kioskId}/alerts/{autoId}     type ('inventory'|'system'),
//                                        title, message, read, timestamp,
//                                        (+ denomination/isBill/qty for
//                                        inventory alerts)
//
// `type` on a transaction/alert is an INPUT→OUTPUT pair using the labels
// the admin app already renders ('bill-coin', 'coin-bill', 'coin-coin',
// 'bill-bill') — see TxType below.
//
// AUTH: every write above requires `request.auth != null` per the rules
// you shared. The kiosk has no login screen, so it signs in anonymously
// at startup (`ensureSignedIn`) — Firebase Auth anonymous users satisfy
// `isSignedIn()` just like a real admin login does. You'll need to enable
// the "Anonymous" sign-in provider in the Firebase console for this to
// work; otherwise every write below will throw.
// ─────────────────────────────────────────────────────────────────────────

/// Input→output combination for a transaction or a dispense, matching the
/// four labels the admin app already knows how to render/color/icon.
enum TxType { billCoin, coinBill, coinCoin, billBill }

extension TxTypeLabel on TxType {
  String get wireValue {
    switch (this) {
      case TxType.billCoin:
        return 'bill-coin';
      case TxType.coinBill:
        return 'coin-bill';
      case TxType.coinCoin:
        return 'coin-coin';
      case TxType.billBill:
        return 'bill-bill';
    }
  }
}

/// One completed/failed/cancelled transaction, written to the top-level
/// `transactions` collection exactly as the admin app's Transactions
/// screen and dashboard charts expect it.
class TransactionRecord {
  final String kioskId;
  final TxType type;
  final double totalValue; // pesos — admin reads input.totalValue
  final String status; // 'completed' | 'cancelled' | 'error'

  TransactionRecord({
    required this.kioskId,
    required this.type,
    required this.totalValue,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'kioskId': kioskId,
        'type': type.wireValue,
        'status': status,
        'input': {'totalValue': totalValue},
        'timestamp': FieldValue.serverTimestamp(),
      };
}

/// A banknote the AI authenticator couldn't confidently clear, written to
/// the top-level `flaggedBills` collection for admin review (Alerts screen
/// + a dedicated review flow on the admin side).
class FlaggedBillRecord {
  final String kioskId;
  final int denomination;
  final double confidence;

  FlaggedBillRecord({
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

/// A hardware/system event surfaced in the admin app's Alerts screen as a
/// `kiosks/{kioskId}/alerts` doc with type 'system'.
class KioskErrorRecord {
  final String code;
  final String message;

  KioskErrorRecord({required this.code, required this.message});
}

/// Wraps Firebase Firestore + Auth for the kiosk, writing into the exact
/// collections/fields the existing Coinvert admin app already reads from.
class FirebaseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final String kioskId;

  FirebaseService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required this.kioskId,
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

  // Local cache of inventory counts, kept in sync via [watchInventory] so
  // dispense writes can decrement-and-check-threshold without a read on
  // every single unit (mirrors what the admin's updateInventoryOnDispense
  // contract expects: caller passes the qty *before* this dispense).
  Map<String, int> _billsCache = {};
  Map<String, int> _coinsCache = {};

  /// Call once at startup, before any other method on this class. Anonymous
  /// auth is what lets the kiosk satisfy `isSignedIn()` in your rules.
  Future<void> ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  /// Logs a completed/cancelled/error transaction. Never throws — a
  /// Firestore hiccup (offline, not signed in yet, rules mismatch) logs to
  /// the console instead of taking down the kiosk UI mid-transaction.
  Future<void> logTransaction(TransactionRecord record) async {
    try {
      await _transactions.add(record.toJson());
    } catch (e) {
      debugPrint('[FirebaseService] logTransaction failed: $e');
    }
  }

  /// Flags a banknote for admin review (low/failed AI confidence).
  Future<void> flagBill(FlaggedBillRecord record) async {
    try {
      await _flaggedBills.add(record.toJson());
    } catch (e) {
      debugPrint('[FirebaseService] flagBill failed: $e');
    }
  }

  /// Logs a hardware/system error as a 'system' alert so it shows up on
  /// the admin app's Alerts screen (System filter).
  Future<void> logError(KioskErrorRecord record) async {
    try {
      await _alerts.add({
        'type': 'system',
        'title': 'Kiosk error: ${record.code}',
        'message': record.message,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirebaseService] logError failed: $e');
    }
  }

  /// Streams `kiosks/{kioskId}/inventory/current` and keeps a local cache
  /// so [recordDispense] can decrement without an extra read per unit.
  Stream<Map<String, dynamic>?> watchInventory() {
    return _inventoryDoc.snapshots().map((doc) {
      final data = doc.data();
      if (data != null) {
        _billsCache = Map<String, int>.from(
            (data['bills'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
        _coinsCache = Map<String, int>.from(
            (data['coins'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
      }
      return data;
    });
  }

  /// Records dispensing [count] units of [denomination] (bill or coin),
  /// decrementing inventory one unit at a time and firing a low-inventory
  /// alert exactly like the admin app's own updateInventoryOnDispense —
  /// this is the kiosk-side half of that same contract, since your rules
  /// block the admin app itself from writing inventory.
  Future<void> recordDispense({
    required String denomination,
    required bool isBill,
    required int count,
    int threshold = 20,
  }) async {
    final cache = isBill ? _billsCache : _coinsCache;
    final denomField = isBill ? 'bills.$denomination' : 'coins.$denomination';

    try {
      for (var i = 0; i < count; i++) {
        final currentQty = cache[denomination] ?? 0;
        final newQty = currentQty - 1;
        cache[denomination] = newQty;

        await _inventoryDoc.update({denomField: newQty});

        if (newQty <= threshold) {
          final existing = await _alerts
              .where('type', isEqualTo: 'inventory')
              .where('denomination', isEqualTo: denomination)
              .where('read', isEqualTo: false)
              .limit(1)
              .get();

          if (existing.docs.isEmpty) {
            final denomLabel = isBill ? '₱$denomination bill' : '₱$denomination coin';
            await _alerts.add({
              'type': 'inventory',
              'title': 'Low inventory: $denomLabel',
              'message': 'Only $newQty unit${newQty == 1 ? '' : 's'} remaining '
                  '(threshold: $threshold)',
              'denomination': denomination,
              'isBill': isBill,
              'qty': newQty,
              'read': false,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[FirebaseService] recordDispense failed: $e');
    }
  }

  /// Admin login — kept for a future companion login screen on this build;
  /// the kiosk's own runtime auth is [ensureSignedIn] (anonymous).
  Future<UserCredential> adminSignIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> adminSignOut() => _auth.signOut();

  bool get isAdminSignedIn => _auth.currentUser != null && !_auth.currentUser!.isAnonymous;
}

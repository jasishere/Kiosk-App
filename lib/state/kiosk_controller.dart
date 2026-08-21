import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/kiosk_step.dart';
import '../services/serial_service.dart';
import '../services/ai_auth_service.dart';
import '../services/firebase_service.dart';

enum ExchangeMode { none, pabarya, pabuo }

enum KioskError { none, hardwareOffline, aiOffline, billRejected, jam, dispenseFailed }

/// Below what AI confidence a *rejected* bill gets escalated to the admin
/// app's `flaggedBills` collection for human review, instead of just being
/// silently rejected at the hardware level.
const double _flagReviewThreshold = 0.60;

/// Drives the actual kiosk transaction flow. This replaces the old
/// "tap next to advance" demo state with real inputs:
///   - Arduino serial events (coins/bills inserted, dispense confirmations)
///   - AI authentication results from the Python/OpenCV service
///   - Firebase logging that matches the existing Coinvert admin app's
///     real Firestore schema (transactions / flaggedBills / kiosk alerts)
///
/// UI screens should be "dumb" — they read from this controller via
/// Provider/ChangeNotifierProvider and call its methods (selectMode,
/// confirmOutput, cancel) rather than owning any transaction state
/// themselves.
class KioskController extends ChangeNotifier {
  final SerialService serial;
  final AiAuthService aiAuth;
  final FirebaseService firebase;

  KioskController({
    required this.serial,
    required this.aiAuth,
    required this.firebase,
  }) {
    _serialSub = serial.events.listen(_onArduinoEvent);
    _connectionSub = serial.connectionState.listen(_onConnectionChange);
    _inventorySub = firebase.watchInventory().listen((_) {});
  }

  StreamSubscription<ArduinoEvent>? _serialSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>?>? _inventorySub;

  KioskStep step = KioskStep.welcome;
  ExchangeMode mode = ExchangeMode.none;
  KioskError error = KioskError.none;
  String? errorDetail;

  int amountInsertedPesos = 0;
  int? lastDenomination;
  double? lastConfidence;

  // Tracks whether cash came in as coins, bills, or both this transaction —
  // used to build the 'bill-coin' / 'coin-bill' / etc. type string the
  // admin app already knows how to label and color.
  bool _hadCoinInput = false;
  bool _hadBillInput = false;
  bool _lastBreakdownIsBills = false;

  bool hardwareConnected = false;
  bool aiServiceOnline = false;

  /// Called once at app startup. Firebase sign-in is wrapped so a
  /// misconfigured/not-yet-set-up Firebase project can't take the whole
  /// UI down with it — you'll still see the kiosk screen and debug panel,
  /// just with transaction/alert logging silently failing until it's fixed.
  Future<void> initialize() async {
    try {
      await firebase.ensureSignedIn();
    } catch (e) {
      debugPrint('Firebase sign-in failed (check firebase_options.dart / '
          'Anonymous auth provider): $e');
    }
    hardwareConnected = serial.connect();
    aiServiceOnline = await aiAuth.healthCheck();
    notifyListeners();
  }

  void _onConnectionChange(bool connected) {
    hardwareConnected = connected;
    if (!connected) {
      _fail(KioskError.hardwareOffline, 'Lost connection to kiosk hardware');
    }
    notifyListeners();
  }

  void _onArduinoEvent(ArduinoEvent event) {
    switch (event.type) {
      case 'COIN':
        _onCashAccepted(event.intArg0);
        break;
      case 'BILL':
        // Sensor-level accept — real authentication happens on BILL_STAGED.
        break;
      case 'BILL_STAGED':
        _authenticateStagedBill(event);
        break;
      case 'BILL_REJECTED':
        _fail(KioskError.billRejected, 'Bill was rejected by the acceptor');
        break;
      case 'DISPENSE_ITEM':
        // Individual item confirmed — could tick a progress counter in the UI.
        break;
      case 'DISPENSE_DONE':
        _onDispenseComplete();
        break;
      case 'DISPENSE_JAM':
      case 'SENSOR_JAM':
        _fail(KioskError.jam, 'Jam detected: ${event.args.join(":")}');
        break;
      case 'ERROR':
        _fail(
          KioskError.hardwareOffline,
          event.args.length > 1 ? event.args[1] : 'Unknown hardware error',
        );
        break;
      default:
        // Unrecognized message — log but never crash (forward-compatible).
        break;
    }
    notifyListeners();
  }

  void _onCashAccepted(int value) {
    amountInsertedPesos += value;
    _hadCoinInput = true;
    notifyListeners();
  }

  Future<void> _authenticateStagedBill(ArduinoEvent event) async {
    step = KioskStep.authenticating;
    notifyListeners();

    serial.uvOn();
    final result = await aiAuth.authenticate();
    serial.captureAck();
    serial.uvOff();

    if (result.errorMessage != null) {
      _fail(KioskError.aiOffline, result.errorMessage!);
      serial.rejectBill();
      return;
    }

    if (result.authentic) {
      serial.acceptBill();
      lastDenomination = result.denomination;
      lastConfidence = result.confidence;
      if (result.denomination != null) {
        amountInsertedPesos += result.denomination!;
        _hadBillInput = true;
      }
      step = KioskStep.insertCash; // back to accepting more, or user hits done
    } else {
      serial.rejectBill();
      // Borderline confidence -> escalate to the admin app for human
      // review instead of just discarding it as a hard rejection.
      if (result.confidence >= _flagReviewThreshold && result.denomination != null) {
        firebase.flagBill(
          FlaggedBillRecord(
            kioskId: firebase.kioskId,
            denomination: result.denomination!,
            confidence: result.confidence,
          ),
        );
      }
      _fail(
        KioskError.billRejected,
        'Banknote failed AI authentication'
        '${result.confidence > 0 ? " (confidence ${(result.confidence * 100).toStringAsFixed(1)}%)" : ""}',
      );
    }
    notifyListeners();
  }

  /// Input→output side of the transaction as one of the admin app's four
  /// labels ('bill-coin' / 'coin-bill' / 'coin-coin' / 'bill-bill').
  TxType get _inputOutputType {
    final outputIsBills = _lastBreakdownIsBills;
    if (_hadBillInput && !_hadCoinInput) {
      return outputIsBills ? TxType.billBill : TxType.billCoin;
    }
    if (_hadCoinInput && !_hadBillInput) {
      return outputIsBills ? TxType.coinBill : TxType.coinCoin;
    }
    // Mixed or no input recorded yet — default to the bill-led label,
    // matching how 'pabarya' (break a bill) is the more common flow.
    return outputIsBills ? TxType.billBill : TxType.billCoin;
  }

  void _onDispenseComplete() async {
    step = KioskStep.complete;
    await firebase.logTransaction(
      TransactionRecord(
        kioskId: firebase.kioskId,
        type: _inputOutputType,
        totalValue: amountInsertedPesos.toDouble(),
        status: 'completed',
      ),
    );
    notifyListeners();
  }

  void _fail(KioskError err, String detail) {
    error = err;
    errorDetail = detail;
    firebase.logError(
      KioskErrorRecord(code: err.name, message: detail),
    );
  }

  // ---------------------------------------------------------------------
  // UI-triggered actions
  // ---------------------------------------------------------------------

  void startTransaction() {
    step = KioskStep.modeSelect;
    notifyListeners();
  }

  void selectMode(ExchangeMode selected) {
    mode = selected;
    step = KioskStep.insertCash;
    notifyListeners();
  }

  /// User pressed "Done inserting" — move on to choosing output.
  void doneInserting() {
    if (amountInsertedPesos <= 0) return;
    step = KioskStep.selectOutput;
    notifyListeners();
  }

  /// User confirmed their desired output mix. `breakdown` maps
  /// denomination -> count, e.g. {20: 5} for 5x ₱20 bills.
  void confirmOutput(Map<int, int> breakdown) {
    step = KioskStep.dispensing;
    _lastBreakdownIsBills = breakdown.keys.every((d) => d >= 20);
    notifyListeners();

    for (final entry in breakdown.entries) {
      // NOTE: denomination-to-type (bill vs coin) mapping should reflect
      // your actual currency rules; ₱20 and up are bills per PROTOCOL/thesis
      // scope, sub-₱20 would be coins if you extend beyond "₱20 and up only".
      final isBill = entry.key >= 20;
      if (isBill) {
        serial.dispenseBill(entry.key, entry.value);
      } else {
        serial.dispenseCoin(entry.key, entry.value);
      }
      // Decrement inventory + fire low-stock alerts to match the admin
      // app's own updateInventoryOnDispense contract.
      firebase.recordDispense(
        denomination: entry.key.toString(),
        isBill: isBill,
        count: entry.value,
      );
    }
  }

  void cancelTransaction() {
    serial.reset();
    firebase.logTransaction(
      TransactionRecord(
        kioskId: firebase.kioskId,
        type: _inputOutputType,
        totalValue: amountInsertedPesos.toDouble(),
        status: 'cancelled',
      ),
    );
    _resetToWelcome();
  }

  void restart() => _resetToWelcome();

  void _resetToWelcome() {
    step = KioskStep.welcome;
    mode = ExchangeMode.none;
    amountInsertedPesos = 0;
    lastDenomination = null;
    lastConfidence = null;
    _hadCoinInput = false;
    _hadBillInput = false;
    _lastBreakdownIsBills = false;
    error = KioskError.none;
    errorDetail = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _serialSub?.cancel();
    _connectionSub?.cancel();
    _inventorySub?.cancel();
    serial.dispose();
    super.dispose();
  }
}

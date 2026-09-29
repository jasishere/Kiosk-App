import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../models/denomination.dart';
import '../models/kiosk_step.dart';
import '../services/ai_auth_service.dart';
import '../services/firebase_service.dart';
import '../services/serial_service.dart';
import 'change_planner.dart';

enum ExchangeMode { none, pabarya, pabuo }

extension ExchangeModeX on ExchangeMode {
  MixPreference get preference => this == ExchangeMode.pabarya
      ? MixPreference.breakDown
      : MixPreference.consolidate;

  String get title => switch (this) {
        ExchangeMode.pabarya => 'Pabarya',
        ExchangeMode.pabuo => 'Pabuo',
        ExchangeMode.none => '',
      };
}

/// An incident inside a transaction, shown over the flow.
enum KioskError { none, jam, dispenseFailed, planUnavailable }

/// Why the kiosk is refusing service. Distinct from [KioskError] because
/// this is a standing condition no customer action can clear.
enum OutageReason { none, hardware, classifier, stockUnknown }

/// A short-lived message shown inline during the insert-cash step — a
/// rejected note, a note the classifier could not read. Deliberately not an
/// error overlay: those tear down the transaction, and tearing down a
/// transaction that already holds the customer's cash is how people lose
/// money to a machine.
class InlineNotice {
  final String message;
  final bool isWarning;
  const InlineNotice(this.message, {this.isWarning = true});
}

/// Escalate a *rejected* note to the admin app for human review when the
/// classifier was this confident or better — below it, the note is simply
/// not a banknote and is not worth a reviewer's time.
const double _flagReviewThreshold = 0.60;

/// Drives the whole transaction. The UI reads from this and calls its
/// methods; no screen owns transaction state.
class KioskController extends ChangeNotifier {
  final SerialService serial;
  final AiAuthService aiAuth;
  final FirebaseService firebase;

  KioskController({
    required this.serial,
    required this.aiAuth,
    required this.firebase,
  });

  StreamSubscription<ArduinoEvent>? _serialSub;
  StreamSubscription<LinkState>? _linkSub;
  StreamSubscription<bool>? _aiSub;
  StreamSubscription<Map<String, dynamic>?>? _inventorySub;
  StreamSubscription<Map<String, dynamic>?>? _configSub;

  Timer? _idleTimer;
  Timer? _statusTimer;
  bool _disposed = false;

  // ── Public state ──────────────────────────────────────────────────────
  KioskStep step = KioskStep.welcome;
  ExchangeMode mode = ExchangeMode.none;
  KioskError error = KioskError.none;
  String? errorDetail;
  InlineNotice? notice;

  /// True while the idle warning banner is up.
  bool idleWarning = false;

  int amountInserted = 0;
  int? lastNoteDenomination;
  double? lastNoteConfidence;

  bool hardwareConnected = false;
  bool classifierOnline = false;

  /// Plan currently being executed, and what has physically landed in the
  /// tray so far — the complete screen reports actual units, not intent.
  DispensePlan? activePlan;
  final Map<DispenseSlot, int> dispensedSoFar = {};

  bool _hadCoinInput = false;
  bool _hadNoteInput = false;
  bool _payoutWasNotes = false;
  bool _transactionSettled = false;

  // ── Readiness ─────────────────────────────────────────────────────────

  /// Notes can only be taken when the classifier is up. When it is down the
  /// kiosk stays open for coins rather than shutting entirely — a classifier
  /// restart shouldn't close a machine that can still do useful work.
  bool get acceptsNotes => classifierOnline;

  OutageReason get outage {
    if (!hardwareConnected) return OutageReason.hardware;
    if (!firebase.inventoryLoaded) return OutageReason.stockUnknown;
    return OutageReason.none;
  }

  bool get canServe => outage == OutageReason.none;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  Future<void> initialize() async {
    _serialSub = serial.events.listen(_onArduinoEvent);
    _linkSub = serial.link.listen(_onLinkChange);
    _aiSub = aiAuth.onlineState.listen(_onClassifierChange);

    // Sign in before subscribing to Firestore. Rules require an
    // authenticated request, and snapshots() does not retry after a
    // permission-denied on its first frame — subscribing too early is what
    // used to leave fee config and stock silently dead for the whole
    // session with nothing surfaced anywhere.
    try {
      await firebase.ensureSignedIn();
    } catch (e) {
      debugPrint('[init] Firebase sign-in failed: $e');
    }

    _inventorySub = firebase.watchInventory().listen(
          (_) => _refresh(),
          onError: (Object e) => debugPrint('[init] inventory stream: $e'),
        );
    _configSub = firebase.watchKioskConfig().listen(
          (_) => _refresh(),
          onError: (Object e) => debugPrint('[init] config stream: $e'),
        );

    hardwareConnected = serial.connect();
    aiAuth.startHealthMonitor();

    _statusTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => firebase.reportStatus(status: canServe ? 'online' : 'fault'),
    );
    unawaited(firebase.reportStatus(status: canServe ? 'online' : 'fault'));

    _applyReadiness();
    _refresh();
  }

  void _refresh() {
    if (_disposed) return;
    _applyReadiness();
    notifyListeners();
  }

  /// Moves in and out of the out-of-service step as conditions change.
  void _applyReadiness() {
    if (!canServe) {
      // Never yank the screen away mid-dispense — let the in-flight
      // sequence finish or fail on its own terms so the customer sees what
      // actually happened to their money.
      if (step.isCommitted) return;
      if (step != KioskStep.outOfService) {
        _clearIdleTimer();
        step = KioskStep.outOfService;
      }
      return;
    }
    if (step == KioskStep.outOfService) {
      step = KioskStep.welcome;
      _resetTransactionState();
    }
  }

  void _onLinkChange(LinkState state) {
    hardwareConnected = state == LinkState.connected;
    if (!hardwareConnected && !step.isCommitted) {
      unawaited(firebase.logError(const KioskErrorRecord(
        code: 'hardware_offline',
        message: 'Serial link to the controller board dropped',
      )));
    }
    _refresh();
  }

  void _onClassifierChange(bool online) {
    classifierOnline = online;
    // Stop taking notes we cannot verify, rather than escrowing one and
    // discovering the classifier is gone with the customer's money inside.
    //
    // Only ever *arm* the acceptors while the customer is actually at the
    // insert step. Enabling them on a classifier recovery that happened to
    // land while the kiosk sat on its welcome screen would leave a live
    // note slot on an idle machine.
    if (online) {
      if (step == KioskStep.insertCash) serial.enableAcceptors();
    } else {
      serial.disableAcceptors();
      unawaited(firebase.logError(const KioskErrorRecord(
        code: 'classifier_offline',
        message: 'Banknote classifier stopped responding; notes disabled',
      )));
    }
    _refresh();
  }

  // ── Arduino events ────────────────────────────────────────────────────

  void _onArduinoEvent(ArduinoEvent event) {
    switch (event.type) {
      case 'COIN':
        _onCoinAccepted(event.intArg(0));
      case 'BILL_STAGED':
        unawaited(_authenticateStagedNote());
      case 'BILL_REJECTED':
        _showNotice('That note was not accepted. Try another one.');
      case 'DISPENSE_JAM':
      case 'SENSOR_JAM':
        _raiseError(KioskError.jam, 'Jam reported: ${event.args.join(' ')}');
      case 'ERROR':
        unawaited(firebase.logError(KioskErrorRecord(
          code: 'firmware_${event.arg(0).toLowerCase()}',
          message: event.arg(1).isEmpty ? event.toString() : event.arg(1),
        )));
      default:
        // DISPENSE_DONE and friends are consumed by SerialService's ack
        // tracking. Anything else is ignored rather than fatal, so newer
        // firmware can add messages without breaking older app builds.
        break;
    }
    notifyListeners();
  }

  void _onCoinAccepted(int value) {
    if (value <= 0) return;
    if (step != KioskStep.insertCash) return;
    if (amountInserted + value > ChangePlanner.maxPayout) {
      _showNotice('That is over the per-transaction limit.');
      return;
    }
    amountInserted += value;
    _hadCoinInput = true;
    _kickIdleTimer();
    notifyListeners();
  }

  Future<void> _authenticateStagedNote() async {
    if (step != KioskStep.insertCash) return;

    step = KioskStep.authenticating;
    notice = null;
    notifyListeners();

    serial.uvOn();
    final result = await aiAuth.authenticate();
    serial.captureAck();
    serial.uvOff();

    // A service outage is not a counterfeit. Return the note and say so
    // plainly, keeping everything already inserted.
    if (result.isServiceError) {
      serial.returnEscrow();
      classifierOnline = false;
      serial.disableAcceptors();
      _showNotice('Note checking is unavailable. Coins only for now.');
      step = KioskStep.insertCash;
      unawaited(firebase.logError(KioskErrorRecord(
        code: 'classifier_error',
        message: result.errorMessage ?? 'unknown classifier error',
      )));
      _refresh();
      return;
    }

    final denomination = result.denomination;

    if (result.authentic && denomination != null && denomination > 0) {
      if (amountInserted + denomination > ChangePlanner.maxPayout) {
        serial.returnEscrow();
        _showNotice('That would go over the per-transaction limit.');
      } else {
        serial.acceptBill();
        amountInserted += denomination;
        lastNoteDenomination = denomination;
        lastNoteConfidence = result.confidence;
        _hadNoteInput = true;
        notice = InlineNotice(
          '${peso_(denomination)} accepted',
          isWarning: false,
        );
      }
    } else {
      serial.rejectBill();
      if (result.confidence >= _flagReviewThreshold && denomination != null) {
        unawaited(firebase.flagBill(FlaggedBillRecord(
          kioskId: firebase.kioskId,
          denomination: denomination,
          confidence: result.confidence,
        )));
        _showNotice('We could not verify that note. It has been returned.');
      } else {
        _showNotice('That note was not recognised. It has been returned.');
      }
    }

    step = KioskStep.insertCash;
    _kickIdleTimer();
    notifyListeners();
  }

  // ── Money maths ───────────────────────────────────────────────────────

  /// Service fee in whole pesos.
  ///
  /// Floored, not rounded. Rounding up could take a peso the customer never
  /// agreed to; flooring also means small transactions land on a ₱0 fee
  /// naturally, with no separate exemption rule to keep in sync.
  int get rawFee {
    if (!firebase.feeEnabled || firebase.feePercent <= 0) return 0;
    final fee = amountInserted * firebase.feePercent / 100;
    return fee.floor().clamp(0, amountInserted);
  }

  /// What the customer is owed before checking it can physically be paid.
  int get grossPayout => amountInserted - rawFee;

  /// The plan the kiosk will actually execute, given live stock and the
  /// chosen mode. Computed on demand and cached per input state — never
  /// inside a build method, because planning touches inventory and used to
  /// write to Firestore on every rebuild.
  DispensePlan get proposedPlan {
    final cacheKey = '$amountInserted|${mode.name}|${firebase.feePercent}';
    if (_planCacheKey == cacheKey && _planCache != null) return _planCache!;

    final plan = ChangePlanner.plan(
      amount: grossPayout,
      stock: firebase.stockSnapshot(),
      preference: mode.preference,
    );
    _planCacheKey = cacheKey;
    _planCache = plan;
    return plan;
  }

  String? _planCacheKey;
  DispensePlan? _planCache;

  /// Value the kiosk can actually hand back right now.
  int get payableAmount => proposedPlan.dispensed;

  /// Fee actually charged. If stock cannot make the exact gross payout, the
  /// difference is absorbed into the fee rather than shorting the customer
  /// without saying so — and [hasShortfall] makes the UI disclose it before
  /// they commit.
  int get effectiveFee => amountInserted - payableAmount;

  bool get hasShortfall => proposedPlan.shortfall > 0;

  /// Minimum to proceed. Pabarya breaks cash into smaller pieces, so there
  /// has to be something worth breaking; pabuo has no floor.
  bool get meetsMinimum {
    if (amountInserted <= 0) return false;
    if (mode == ExchangeMode.pabarya) return amountInserted >= 20;
    return true;
  }

  /// Guard for the confirm button: the kiosk must be able to pay something.
  bool get canConfirmPayout => payableAmount > 0 && proposedPlan.isExact;

  TxType get _txType {
    if (_hadNoteInput && !_hadCoinInput) {
      return _payoutWasNotes ? TxType.billBill : TxType.billCoin;
    }
    if (_hadCoinInput && !_hadNoteInput) {
      return _payoutWasNotes ? TxType.coinBill : TxType.coinCoin;
    }
    return _payoutWasNotes ? TxType.billBill : TxType.billCoin;
  }

  // ── Customer actions ──────────────────────────────────────────────────

  void startTransaction() {
    if (!canServe) return;
    step = KioskStep.modeSelect;
    _kickIdleTimer();
    notifyListeners();
  }

  void selectMode(ExchangeMode selected) {
    mode = selected;
    step = KioskStep.insertCash;
    _invalidatePlan();
    if (acceptsNotes) {
      serial.enableAcceptors();
    } else {
      serial.disableAcceptors();
    }
    _kickIdleTimer();
    notifyListeners();
  }

  void doneInserting() {
    if (!meetsMinimum) return;
    serial.disableAcceptors();
    step = KioskStep.selectOutput;
    _invalidatePlan();
    _kickIdleTimer();
    notifyListeners();
  }

  /// Confirms a payout mix and runs it.
  ///
  /// [plan] must be exact. A short plan is refused outright rather than
  /// dispensed with an alert filed somewhere the customer will never see.
  Future<void> confirmPayout(DispensePlan plan) async {
    if (step != KioskStep.selectOutput) return;
    if (plan.isEmpty || !plan.isExact) {
      _raiseError(
        KioskError.planUnavailable,
        'The kiosk cannot make that exact amount from the cash it holds.',
      );
      return;
    }
    await _runDispense(plan);
  }

  /// Steps through the hoppers one denomination at a time, waiting for each
  /// to confirm before starting the next.
  ///
  /// The previous version wrote every DISPENSE command in a loop and then
  /// treated the first DISPENSE_DONE as the whole payout finishing — so the
  /// transaction was logged as complete, and the customer told to collect
  /// their cash, while the remaining hoppers were still running.
  Future<void> _runDispense(DispensePlan plan) async {
    _clearIdleTimer();
    step = KioskStep.dispensing;
    activePlan = plan;
    dispensedSoFar.clear();
    _payoutWasNotes = plan.units.keys.every((s) => s.isBill);
    _transactionSettled = false;
    notifyListeners();

    // Largest first: if something fails partway, the customer has already
    // received most of what they are owed, which makes the manual
    // reconciliation far smaller.
    final ordered = plan.units.entries.toList()
      ..sort((a, b) => b.key.value.compareTo(a.key.value));

    for (final entry in ordered) {
      try {
        final moved = await serial.dispense(
          value: entry.key.value,
          isBill: entry.key.isBill,
          count: entry.value,
        );
        dispensedSoFar[entry.key] = moved;
        notifyListeners();

        if (moved < entry.value) {
          await _settleDispense(
            status: 'error',
            failureMessage:
                'The ${entry.key.label} hopper released $moved of ${entry.value}.',
          );
          return;
        }
      } on DispenseException catch (e) {
        if (e.dispensed > 0) dispensedSoFar[entry.key] = e.dispensed;
        await _settleDispense(status: 'error', failureMessage: e.message);
        return;
      } catch (e) {
        await _settleDispense(status: 'error', failureMessage: '$e');
        return;
      }
    }

    await _settleDispense(status: 'completed');
  }

  /// Writes inventory and the transaction record exactly once, from what
  /// physically moved rather than what was planned.
  Future<void> _settleDispense({
    required String status,
    String? failureMessage,
  }) async {
    if (_transactionSettled) return;
    _transactionSettled = true;

    final paid = dispensedSoFar.entries
        .fold<int>(0, (sum, e) => sum + e.key.value * e.value);

    await firebase.recordDispense(Map.of(dispensedSoFar));
    await firebase.logTransaction(TransactionRecord(
      kioskId: firebase.kioskId,
      type: _txType,
      totalValue: amountInserted.toDouble(),
      status: status,
      feeCharged: (amountInserted - paid).toDouble(),
      payoutValue: paid.toDouble(),
      breakdown: {
        for (final e in dispensedSoFar.entries) e.key.id: e.value,
      },
    ));

    if (failureMessage != null) {
      await firebase.logError(KioskErrorRecord(
        code: 'dispense_failed',
        message: '$failureMessage Paid ${peso_(paid)} of '
            '${peso_(activePlan?.dispensed ?? 0)}.',
      ));
      _raiseError(KioskError.dispenseFailed, failureMessage);
    } else {
      step = KioskStep.complete;
    }
    notifyListeners();
  }

  /// Cancel. Only meaningful before any cash has been taken.
  ///
  /// Once notes and coins are inside, there is nothing honest to cancel to:
  /// accepted cash has already left escrow and cannot be handed back as the
  /// same pieces. Rather than pretending otherwise, the kiosk moves the
  /// customer to choosing a payout so they leave with their money.
  void cancelTransaction() {
    if (step.isCommitted) return;

    if (amountInserted > 0) {
      serial.disableAcceptors();
      step = KioskStep.selectOutput;
      _showNotice(
        'Cash already inserted cannot be returned as-is. '
        'Choose how you would like it back.',
      );
      _kickIdleTimer();
      notifyListeners();
      return;
    }

    serial.disableAcceptors();
    serial.returnEscrow();
    _resetToWelcome();
  }

  void dismissError() {
    error = KioskError.none;
    errorDetail = null;
    // A failed dispense leaves the machine in a state only an attendant can
    // reconcile, so it goes to the completion summary rather than pretending
    // the transaction can restart.
    step = amountInserted > 0 ? KioskStep.complete : KioskStep.welcome;
    notifyListeners();
  }

  void restart() => _resetToWelcome();

  // ── Idle watchdog ─────────────────────────────────────────────────────

  void _kickIdleTimer() {
    idleWarning = false;
    _idleTimer?.cancel();
    if (!step.isTransactional) return;
    _idleTimer = Timer(AppConfig.idleWarning, _onIdleWarning);
  }

  void _clearIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    idleWarning = false;
  }

  void _onIdleWarning() {
    if (!step.isTransactional) return;
    idleWarning = true;
    notifyListeners();
    _idleTimer = Timer(AppConfig.idleGrace, _onIdleExpired);
  }

  /// Someone walked away. If they left money in the machine, pay it out
  /// rather than resetting and keeping it — an unattended kiosk that
  /// silently absorbs abandoned cash is both a support nightmare and, at
  /// scale, indistinguishable from theft.
  void _onIdleExpired() {
    idleWarning = false;
    if (amountInserted > 0) {
      final plan = proposedPlan;
      if (plan.isExact && !plan.isEmpty) {
        unawaited(_runDispense(plan));
        return;
      }
      unawaited(firebase.logError(KioskErrorRecord(
        code: 'abandoned_cash',
        message: 'Customer left ${peso_(amountInserted)} and the kiosk could '
            'not assemble a payout. Attendant reconciliation required.',
      )));
      _raiseError(
        KioskError.planUnavailable,
        'Please ask the attendant for assistance.',
      );
      return;
    }
    _resetToWelcome();
  }

  /// Any touch anywhere restarts the countdown.
  void registerInteraction() {
    if (!step.isTransactional) return;
    if (idleWarning) {
      idleWarning = false;
      notifyListeners();
    }
    _kickIdleTimer();
  }

  // ── Internals ─────────────────────────────────────────────────────────

  void _showNotice(String message, {bool isWarning = true}) {
    notice = InlineNotice(message, isWarning: isWarning);
  }

  void clearNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  void _raiseError(KioskError kind, String detail) {
    error = kind;
    errorDetail = detail;
    notifyListeners();
  }

  void _invalidatePlan() {
    _planCacheKey = null;
    _planCache = null;
  }

  void _resetTransactionState() {
    mode = ExchangeMode.none;
    amountInserted = 0;
    lastNoteDenomination = null;
    lastNoteConfidence = null;
    _hadCoinInput = false;
    _hadNoteInput = false;
    _payoutWasNotes = false;
    _transactionSettled = false;
    activePlan = null;
    dispensedSoFar.clear();
    error = KioskError.none;
    errorDetail = null;
    notice = null;
    _invalidatePlan();
  }

  void _resetToWelcome() {
    _clearIdleTimer();
    serial.disableAcceptors();
    _resetTransactionState();
    step = canServe ? KioskStep.welcome : KioskStep.outOfService;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _statusTimer?.cancel();
    _serialSub?.cancel();
    _linkSub?.cancel();
    _aiSub?.cancel();
    _inventorySub?.cancel();
    _configSub?.cancel();
    unawaited(serial.dispose());
    aiAuth.dispose();
    super.dispose();
  }
}

/// Local peso formatter — kept here so the controller has no dependency on
/// the theme layer.
String peso_(int amount) => '₱$amount';

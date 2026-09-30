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

enum KioskError { none, dispenseFailed, planUnavailable }

enum OutageReason { none, hardware, stockUnknown }

class InlineNotice {
  final String message;
  final bool isWarning;
  const InlineNotice(this.message, {this.isWarning = true});
}

const double _flagReviewThreshold = 0.60;

/// Drives the whole transaction against `coinvert_firmware.ino` (Uno +
/// PCA9685 build). Two things about this specific firmware shape the whole
/// design here, worth keeping in mind while reading this file:
///
/// 1. **The acceptor is hardware-gated via `ACCEPTOR:ON`/`ACCEPTOR:OFF`**,
///    which drives the acceptor's own enable/inhibit line
///    (`PIN_BILL_ACCEPTOR_ENABLE` in the .ino) — added specifically so an
///    unverifiable note can be refused before it's ever fed in, not just
///    rejected afterward. It is only ever armed while the customer is at
///    the insert step AND the classifier is online (see [_syncAcceptorGate])
///    — everywhere else, including the instant the classifier drops offline
///    mid-transaction, it's disabled.
/// 2. **The firmware tracks its own running credit** and reports it after
///    every accepted coin, accepted bill, and completed dispense via
///    `CREDIT:<pesos>`. Rather than maintain a second, potentially
///    drifting copy of that number in Dart, [amountInserted] is driven
///    directly by that line — the firmware is the source of truth for how
///    much cash physically went in.
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

  KioskStep step = KioskStep.welcome;
  ExchangeMode mode = ExchangeMode.none;
  KioskError error = KioskError.none;
  String? errorDetail;
  InlineNotice? notice;
  bool idleWarning = false;

  /// Driven by the firmware's own `CREDIT:` line — see class doc.
  int amountInserted = 0;

  /// The value of a bill currently mid-authentication, from `BILL:VALUE:`.
  /// Not yet part of [amountInserted] — the firmware only credits it once
  /// this app answers `BILL:ACCEPT` and the board confirms.
  int? _pendingBillValue;

  int? lastNoteDenomination;
  double? lastNoteConfidence;

  bool hardwareConnected = false;
  bool classifierOnline = false;

  DispensePlan? activePlan;
  final Map<DispenseSlot, int> dispensedSoFar = {};

  bool _hadCoinInput = false;
  bool _hadNoteInput = false;
  bool _payoutWasNotes = false;
  bool _transactionSettled = false;

  /// Whether the app WANTS the acceptor armed right now. This does not by
  /// itself send anything — see [_syncAcceptorGate], which is the only
  /// place that actually calls enableAcceptor()/disableAcceptor(), so the
  /// hardware state can't drift out of sync with this by being set from
  /// two different call sites.
  bool get _shouldAcceptorBeArmed =>
      step == KioskStep.insertCash && classifierOnline && hardwareConnected;

  bool _acceptorArmed = false;

  /// The single point where the acceptor's hardware gate is actually
  /// changed. Call this after anything that could change
  /// [_shouldAcceptorBeArmed] — a step transition, a classifier state
  /// change, a link state change — rather than calling
  /// enableAcceptor()/disableAcceptor() directly elsewhere.
  void _syncAcceptorGate() {
    final want = _shouldAcceptorBeArmed;
    if (want == _acceptorArmed) return;
    _acceptorArmed = want;
    if (want) {
      serial.enableAcceptor();
    } else {
      serial.disableAcceptor();
    }
  }

  /// Whether the app will actually act on a bill reaching the acceptor.
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
    _syncAcceptorGate();
    _refresh();
  }

  void _refresh() {
    if (_disposed) return;
    _applyReadiness();
    notifyListeners();
  }

  void _applyReadiness() {
    if (!canServe) {
      if (step.isCommitted) return;
      if (step != KioskStep.outOfService) {
        _clearIdleTimer();
        step = KioskStep.outOfService;
        _syncAcceptorGate();
      }
      return;
    }
    if (step == KioskStep.outOfService) {
      step = KioskStep.welcome;
      _resetTransactionState();
      _syncAcceptorGate();
    }
  }

  void _onLinkChange(LinkState state) {
    hardwareConnected = state == LinkState.connected;
    if (!hardwareConnected) {
      // The link just dropped — _acceptorArmed can't be trusted to still
      // reflect reality on the board (it may have reset), so force a
      // resync attempt regardless of the memoised want/armed comparison.
      _acceptorArmed = false;
    }
    if (!hardwareConnected && !step.isCommitted) {
      unawaited(firebase.logError(const KioskErrorRecord(
        code: 'hardware_offline',
        message: 'Serial link to the controller board dropped',
      )));
    }
    _syncAcceptorGate();
    _refresh();
  }

  void _onClassifierChange(bool online) {
    classifierOnline = online;
    if (!online) {
      unawaited(firebase.logError(const KioskErrorRecord(
        code: 'classifier_offline',
        message:
            'Banknote classifier stopped responding; bills will be mechanically '
            'accepted by the acceptor but auto-rejected before being credited, '
            'since this firmware has no acceptor-gating command.',
      )));
    }
    _syncAcceptorGate();
    _refresh();
  }

  // ── Arduino events ────────────────────────────────────────────────────

  void _onArduinoEvent(ArduinoEvent event) {
    switch (event.type) {
      case 'READY':
        // Board just booted/reset. Nothing to do beyond noting it arrived —
        // link state is already tracked separately via LinkState.
        break;

      case 'BILL':
        _onBillEvent(event);

      case 'COIN':
        _onCoinEvent(event);

      case 'CREDIT':
        // Firmware's own running total — see class doc. This is the only
        // place amountInserted is ever set for money already inside the
        // machine.
        amountInserted = event.intArg(0);

      case 'DISPENSE':
        // Ack routing for an in-flight dispense is handled inside
        // SerialService itself (it resolves the pending Future). Nothing
        // additional needed here beyond letting the event flow through for
        // any future logging.
        break;

      case 'UNKNOWN':
        // The firmware echoes back anything it didn't recognise — useful
        // for catching a stale command from an old build, logged but not
        // fatal.
        debugPrint('[arduino] firmware did not recognise: ${event.args.join(':')}');

      default:
        break;
    }
    notifyListeners();
  }

  void _onBillEvent(ArduinoEvent event) {
    final sub = event.arg(0).toUpperCase();
    switch (sub) {
      case 'VALUE':
        _pendingBillValue = event.intArg(1);

      case 'READY_UV':
        // This is the app's one and only window to act: the firmware runs
        // its own fixed-timer sequence from here (UV hold → visible hold →
        // an 8s verdict wait) and will default to reject if this app never
        // answers. Kick off authentication now rather than waiting for
        // READY_VISIBLE — that leaves the most possible margin against the
        // firmware's own timeout.
        unawaited(_authenticatePendingBill());

      case 'READY_VISIBLE':
        // Visible-light stage started. Nothing to do — this build's
        // classifier contract authenticates from a single UV-lit capture;
        // see AiAuthService's doc if that ever changes to want a second
        // image from this stage.
        break;

      case 'DONE':
        final verdict = event.arg(1).toUpperCase();
        if (verdict == 'ACCEPT') {
          _hadNoteInput = true;
          notice = InlineNotice(
            '${lastNoteDenomination != null ? peso_(lastNoteDenomination!) : 'Note'} accepted',
            isWarning: false,
          );
        } else {
          notice = const InlineNotice(
            'That note was not accepted. It has been returned.',
          );
        }
        _pendingBillValue = null;
        if (step == KioskStep.authenticating) step = KioskStep.insertCash;
        _syncAcceptorGate();
        _kickIdleTimer();
    }
  }

  void _onCoinEvent(ArduinoEvent event) {
    if (event.arg(0).toUpperCase() != 'VALUE') return;
    if (step != KioskStep.insertCash) return;
    _hadCoinInput = true;
    _kickIdleTimer();
    // amountInserted itself is updated by the CREDIT: line that follows
    // this immediately in the firmware — nothing to add here.
  }

  Future<void> _authenticatePendingBill() async {
    if (step != KioskStep.insertCash) return;

    step = KioskStep.authenticating;
    notice = null;
    _syncAcceptorGate();
    notifyListeners();

    if (!classifierOnline) {
      // Can't verify it — see class doc point 1. Reject before it's ever
      // credited rather than accept something unverified.
      serial.rejectBill();
      _pendingBillValue = null;
      step = KioskStep.insertCash;
      _syncAcceptorGate();
      _showNotice('Note checking is offline, so notes can\'t be accepted '
          'right now. Coins only, sorry.');
      _refresh();
      return;
    }

    final result = await aiAuth.authenticate();

    if (result.isServiceError) {
      // A service outage is not a counterfeit determination — the bill
      // still can't be credited, but say why plainly.
      serial.rejectBill();
      classifierOnline = false;
      _pendingBillValue = null;
      step = KioskStep.insertCash;
      _syncAcceptorGate();
      _showNotice('Note checking is unavailable. Coins only for now.');
      unawaited(firebase.logError(KioskErrorRecord(
        code: 'classifier_error',
        message: result.errorMessage ?? 'unknown classifier error',
      )));
      _refresh();
      return;
    }

    final claimed = _pendingBillValue;
    final denomination = result.denomination;

    if (result.authentic &&
        denomination != null &&
        denomination > 0 &&
        claimed != null &&
        // The classifier's read must agree with what the acceptor's own
        // pulse count claimed. A mismatch here — genuine note but a
        // different denomination than the acceptor thinks — is treated as
        // a reason to reject rather than trust either signal alone.
        denomination == claimed) {
      if (amountInserted + denomination > ChangePlanner.maxPayout) {
        serial.rejectBill();
        _showNotice('That would go over the per-transaction limit.');
      } else {
        lastNoteDenomination = denomination;
        lastNoteConfidence = result.confidence;
        serial.acceptBill();
        // amountInserted updates once the firmware's own CREDIT: line
        // follows BILL:DONE:ACCEPT — not set directly here.
      }
    } else {
      serial.rejectBill();
      if (result.confidence >= _flagReviewThreshold && denomination != null) {
        unawaited(firebase.flagBill(FlaggedBillRecord(
          kioskId: firebase.kioskId,
          denomination: denomination,
          confidence: result.confidence,
        )));
      }
    }

    // Step transition and any acceptance/rejection notice both happen once
    // BILL:DONE:<verdict> actually arrives (see _onBillEvent) — that's the
    // firmware confirming the sort motion ran, not just that this app made
    // a decision.
    _kickIdleTimer();
  }

  // ── Money maths (unchanged from the value-based design) ───────────────

  int get rawFee {
    if (!firebase.feeEnabled || firebase.feePercent <= 0) return 0;
    final fee = amountInserted * firebase.feePercent / 100;
    return fee.floor().clamp(0, amountInserted);
  }

  int get grossPayout => amountInserted - rawFee;

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

  int get payableAmount => proposedPlan.dispensed;
  int get effectiveFee => amountInserted - payableAmount;
  bool get hasShortfall => proposedPlan.shortfall > 0;

  bool get meetsMinimum {
    if (amountInserted <= 0) return false;
    if (mode == ExchangeMode.pabarya) return amountInserted >= 20;
    return true;
  }

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
    _syncAcceptorGate();
    _kickIdleTimer();
    notifyListeners();
  }

  void doneInserting() {
    if (!meetsMinimum) return;
    step = KioskStep.selectOutput;
    _invalidatePlan();
    _syncAcceptorGate();
    _kickIdleTimer();
    notifyListeners();
  }

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

  /// Sequences dispensing one denomination at a time, same principle as
  /// before, translated to this firmware's lane addressing. Largest value
  /// first, so a failure partway through leaves the customer already
  /// holding most of what they're owed.
  Future<void> _runDispense(DispensePlan plan) async {
    _clearIdleTimer();
    step = KioskStep.dispensing;
    _syncAcceptorGate();
    activePlan = plan;
    dispensedSoFar.clear();
    _payoutWasNotes = plan.units.keys.every((s) => s.isBill);
    _transactionSettled = false;
    notifyListeners();

    final ordered = plan.units.entries.toList()
      ..sort((a, b) => b.key.value.compareTo(a.key.value));

    for (final entry in ordered) {
      final slot = entry.key;
      final lane = slot.isBill
          ? DenominationLanes.billLane(slot.value)
          : DenominationLanes.coinLane(slot.value);

      if (lane < 0) {
        // The app's denomination list and the firmware's lane arrays have
        // drifted out of sync — see docs/HARDWARE.md. This must never
        // silently skip the payout.
        await _settleDispense(
          status: 'error',
          failureMessage:
              '${slot.label} has no matching lane on this board. The app '
              'and firmware denomination lists are out of sync.',
        );
        return;
      }

      try {
        final moved = await serial.dispenseAtLane(
          lane: lane,
          isBill: slot.isBill,
          count: entry.value,
        );
        dispensedSoFar[slot] = moved;
        notifyListeners();
      } on DispenseException catch (e) {
        // This firmware has no partial-progress reporting — a failure here
        // means nothing on this lane was confirmed at all this round.
        await _settleDispense(status: 'error', failureMessage: e.message);
        return;
      } catch (e) {
        await _settleDispense(status: 'error', failureMessage: '$e');
        return;
      }
    }

    await _settleDispense(status: 'completed');
  }

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
    _syncAcceptorGate();
    notifyListeners();
  }

  /// Cancel. Only meaningful before any cash has been taken — see the note
  /// on this in the value-based design; unchanged here. Once cash is in,
  /// the firmware's own credit is already non-zero and there's no honest
  /// "give back exactly what was inserted," so the customer is moved to
  /// choosing a payout instead.
  void cancelTransaction() {
    if (step.isCommitted) return;

    if (amountInserted > 0) {
      step = KioskStep.selectOutput;
      _syncAcceptorGate();
      _showNotice(
        'Cash already inserted cannot be returned as-is. '
        'Choose how you would like it back.',
      );
      _kickIdleTimer();
      notifyListeners();
      return;
    }

    _resetToWelcome();
  }

  void dismissError() {
    error = KioskError.none;
    errorDetail = null;
    step = amountInserted > 0 ? KioskStep.complete : KioskStep.welcome;
    _syncAcceptorGate();
    notifyListeners();
  }

  void restart() => _resetToWelcome();

  // ── Idle watchdog (unchanged) ─────────────────────────────────────────

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
    // amountInserted is NOT reset to 0 here directly — it reflects the
    // firmware's own credit, which only the firmware changes. A fresh
    // transaction genuinely starting at zero relies on the firmware having
    // already zeroed its credit after the previous payout completed.
    lastNoteDenomination = null;
    lastNoteConfidence = null;
    _pendingBillValue = null;
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
    _resetTransactionState();
    step = canServe ? KioskStep.welcome : KioskStep.outOfService;
    _syncAcceptorGate();
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

String peso_(int amount) => '₱$amount';

/// Steps in the customer-facing flow.
enum KioskStep {
  /// Idle attract screen.
  welcome,

  /// Choosing pabarya or pabuo.
  modeSelect,

  /// Feeding coins and notes.
  insertCash,

  /// A note is in escrow under the UV camera, awaiting the classifier.
  authenticating,

  /// Choosing how to receive the payout.
  selectOutput,

  /// Hoppers are running.
  dispensing,

  /// Payout finished, cash in the tray.
  complete,

  /// The kiosk cannot safely take money — hardware down, classifier down,
  /// or stock levels unknown. A dedicated step rather than an error overlay
  /// because it is a standing condition, not an incident inside a
  /// transaction, and no customer input can clear it.
  outOfService,
}

extension KioskStepX on KioskStep {
  String get label => switch (this) {
        KioskStep.welcome => 'Welcome',
        KioskStep.modeSelect => 'Choose a service',
        KioskStep.insertCash => 'Insert cash',
        KioskStep.authenticating => 'Checking note',
        KioskStep.selectOutput => 'Choose your cash',
        KioskStep.dispensing => 'Dispensing',
        KioskStep.complete => 'Done',
        KioskStep.outOfService => 'Out of service',
      };

  /// Steps where the customer is mid-transaction and may have money in the
  /// machine — these get the idle watchdog and a visible ledger.
  bool get isTransactional => switch (this) {
        KioskStep.modeSelect ||
        KioskStep.insertCash ||
        KioskStep.authenticating ||
        KioskStep.selectOutput =>
          true,
        _ => false,
      };

  /// Steps that must not be interrupted by an idle timeout or a cancel.
  bool get isCommitted =>
      this == KioskStep.dispensing || this == KioskStep.authenticating;
}

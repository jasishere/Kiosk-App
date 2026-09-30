/// Wire protocol matching `coinvert_firmware.ino` (Uno + PCA9685 version)
/// exactly. If you change a message on the firmware side, mirror it here —
/// this file and the .ino are the two halves of one contract.
///
/// Key differences from a "one hopper per denomination" design:
///  - Denominations are addressed by **lane index** into the firmware's own
///    fixed arrays (`coinLaneValue[4]`, `billLaneValue[5]`), not by peso
///    value. `DenominationLanes` below is the translation table — it must
///    stay byte-for-byte identical to those two arrays in the .ino.
///  - There is no per-dispense confirmed-count field. `DISPENSE:COIN:DONE:2`
///    means "lane 2 finished," full stop — the firmware has no sensor
///    checking whether coins actually left the compartment, so "done" here
///    means "the servo motion completed," not "N units were verified
///    delivered." Treat every dispense as best-effort until/unless a
///    confirmation sensor is added and this protocol is revised to report a
///    count.
///  - Bill authentication timing is autonomous on the firmware: once a bill
///    is inserted, the board runs its own UV → visible-light → verdict-wait
///    sequence on fixed timers and narrates each stage. The Pi's only job is
///    to capture at the right stage and answer with BILL:ACCEPT/REJECT
///    before the firmware's own timeout defaults to reject.
library;

/// One parsed line from the Arduino. Lines are colon-delimited ASCII
/// terminated by `\n`.
class ArduinoEvent {
  final String type;
  final List<String> args;

  const ArduinoEvent(this.type, [this.args = const []]);

  factory ArduinoEvent.parse(String line) {
    final parts = line.trim().split(':');
    return ArduinoEvent(parts.first.toUpperCase(), parts.skip(1).toList());
  }

  String arg(int i) => i < args.length ? args[i] : '';
  int intArg(int i) => int.tryParse(arg(i)) ?? 0;

  @override
  String toString() => args.isEmpty ? type : '$type:${args.join(':')}';
}

enum LinkState { disconnected, connecting, connected, stale }

/// Lane-index tables. **Must match `coinLaneValue`/`billLaneValue` in the
/// .ino exactly** — order and values both. There is no discovery mechanism;
/// if the firmware's arrays change, update these two lists by hand.
class DenominationLanes {
  const DenominationLanes._();

  static const List<int> coinValues = [1, 5, 10, 20];
  static const List<int> billValues = [50, 100, 200, 500, 1000];

  /// Lane index for a coin of [value], or -1 if there's no lane for it.
  static int coinLane(int value) => coinValues.indexOf(value);

  /// Lane index for a bill of [value], or -1 if there's no lane for it.
  static int billLane(int value) => billValues.indexOf(value);

  static int? coinValueForLane(int lane) =>
      (lane >= 0 && lane < coinValues.length) ? coinValues[lane] : null;

  static int? billValueForLane(int lane) =>
      (lane >= 0 && lane < billValues.length) ? billValues[lane] : null;
}

/// Commands the Pi sends to the Arduino.
class ArduinoCommand {
  const ArduinoCommand._();

  static const ping = 'PING';
  static const billAccept = 'BILL:ACCEPT';
  static const billReject = 'BILL:REJECT';
  static const acceptorOn = 'ACCEPTOR:ON';
  static const acceptorOff = 'ACCEPTOR:OFF';
  static const status = 'STATUS';

  /// Dispenses [count] units from coin lane [lane] (0..3).
  static String dispenseCoin(int lane, int count) =>
      'DISPENSE:COIN:$lane:$count';

  /// Dispenses [count] units from bill lane [lane] (0..4).
  static String dispenseBill(int lane, int count) =>
      'DISPENSE:BILL:$lane:$count';

  // Test-only — not used in the production flow, kept for bench diagnostics
  // via the service panel.
  static const testUvOn = 'TEST:UV:ON';
  static const testUvOff = 'TEST:UV:OFF';
  static const testSortAccept = 'TEST:SORT:ACCEPT';
  static const testSortReject = 'TEST:SORT:REJECT';
  static const testSortNeutral = 'TEST:SORT:NEUTRAL';
  static const testRollerOn = 'TEST:ROLLER:ON';
  static const testRollerOff = 'TEST:ROLLER:OFF';
  static String testCoin(int lane) => 'TEST:COIN:$lane';
  static String testBill(int lane) => 'TEST:BILL:$lane';
}

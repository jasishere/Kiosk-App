/// Wire protocol shared by both SerialService implementations.
/// The authoritative message list lives in docs/HARDWARE.md — keep the two
/// in step when you add a message.

/// One parsed line from the Arduino. Lines are colon-delimited ASCII
/// terminated by `\n`, e.g. `COIN:5` or `DISPENSE_DONE:COIN:5:3`.
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

/// Why the serial link is in the state it's in — lets the UI distinguish
/// "never plugged in" from "was fine, went quiet", which need different
/// messages on the service panel.
enum LinkState { disconnected, connecting, connected, stale }

/// Commands the Pi sends to the Arduino. Centralised so the firmware's
/// parser and this app can't drift apart silently.
class ArduinoCommand {
  const ArduinoCommand._();

  static const reset = 'RESET';
  static const ping = 'PING';
  static const uvOn = 'UV:ON';
  static const uvOff = 'UV:OFF';
  static const captureAck = 'CAPTURE_ACK';
  static const acceptBill = 'ACCEPT_BILL';
  static const rejectBill = 'REJECT_BILL';
  static const returnEscrow = 'RETURN_ESCROW';
  static const acceptorEnable = 'ACCEPTOR:ON';
  static const acceptorDisable = 'ACCEPTOR:OFF';

  static String dispense(int value, bool isBill, int count) =>
      'DISPENSE:${isBill ? 'BILL' : 'COIN'}:$value:$count';
}

import 'dart:async';

/// Parsed event coming from the Arduino Mega.
/// See /PROTOCOL.md for the full message list.
class ArduinoEvent {
  final String type; // e.g. "COIN", "BILL", "DISPENSE_DONE"
  final List<String> args; // remaining colon-delimited fields

  ArduinoEvent(this.type, this.args);

  factory ArduinoEvent.parse(String line) {
    final parts = line.trim().split(':');
    return ArduinoEvent(parts.first, parts.skip(1).toList());
  }

  int get intArg0 => int.tryParse(args.isNotEmpty ? args[0] : '') ?? 0;

  @override
  String toString() => '${type}${args.isEmpty ? '' : ':${args.join(':')}'}';
}

/// Web build of SerialService. Real USB serial isn't reachable from a
/// browser at all, so this only supports [simulate] mode — same public
/// API as the real (io) implementation, so KioskController and the UI
/// never need to know which one they got. Used automatically when
/// building for web; the real dart:ffi-backed version is used on
/// desktop/mobile (see serial_service.dart for the conditional import).
class SerialService {
  final String portName;
  final int baudRate;
  final bool simulate;

  final _eventController = StreamController<ArduinoEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  SerialService({
    this.portName = '/dev/ttyACM0',
    this.baudRate = 115200,
    this.simulate = false,
  });

  Stream<ArduinoEvent> get events => _eventController.stream;
  Stream<bool> get connectionState => _connectionController.stream;
  bool get isOpen => simulate;

  bool connect() {
    if (simulate) {
      _connectionController.add(true);
      return true;
    }
    // Real serial isn't available on web — nothing to connect to.
    _connectionController.add(false);
    return false;
  }

  void send(String command) {
    if (simulate) {
      // ignore: avoid_print
      print('[SIM/web] -> Arduino: $command');
    }
    // No-op on real (non-simulate) web builds — there's no port to write to.
  }

  // ── Simulation helpers ────────────────────────────────────────────────
  void simulateCoin(int pesos) =>
      _eventController.add(ArduinoEvent('COIN', ['$pesos']));

  void simulateBillStaged() => _eventController.add(ArduinoEvent('BILL_STAGED', []));

  void simulateBillRejectedByAcceptor() =>
      _eventController.add(ArduinoEvent('BILL_REJECTED', []));

  void simulateDispenseDone() =>
      _eventController.add(ArduinoEvent('DISPENSE_DONE', []));

  void simulateJam() =>
      _eventController.add(ArduinoEvent('DISPENSE_JAM', ['SIM']));

  void simulateHardwareError(String message) =>
      _eventController.add(ArduinoEvent('ERROR', ['SIM', message]));

  // Convenience command helpers — mirrors PROTOCOL.md "Pi -> Arduino" table.
  void reset() => send('RESET');
  void uvOn() => send('UV:ON');
  void uvOff() => send('UV:OFF');
  void captureAck() => send('CAPTURE_ACK');
  void acceptBill() => send('ACCEPT_BILL');
  void rejectBill() => send('REJECT_BILL');
  void dispenseBill(int denom, int count) =>
      send('DISPENSE:BILL:$denom:$count');
  void dispenseCoin(int denom, int count) =>
      send('DISPENSE:COIN:$denom:$count');
  void ping() => send('PING');

  void dispose() {
    _eventController.close();
    _connectionController.close();
  }
}

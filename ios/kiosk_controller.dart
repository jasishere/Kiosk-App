import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

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

/// Wraps the USB serial connection to the Arduino Mega.
///
/// Uses `flutter_libserialport` (works on Linux, which is what the
/// Raspberry Pi 5 kiosk build will run). Add to pubspec.yaml:
///   flutter_libserialport: ^0.4.0
///
/// On the Pi, the Arduino Mega typically enumerates as /dev/ttyACM0.
/// Run `dmesg | grep tty` after plugging it in if the port differs.
class SerialService {
  final String portName;
  final int baudRate;

  /// When true, no real serial port is touched at all — [connect] just
  /// reports "connected" and every `send()` (dispense, UV, etc.) is a
  /// no-op that's only printed to the console. Use the `simulateXxx()`
  /// methods below to feed fake Arduino events into the same [events]
  /// stream the real hardware would use, so you can exercise the whole
  /// KioskController/UI flow on a laptop before the Pi + Arduino exist.
  final bool simulate;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;

  final _eventController = StreamController<ArduinoEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  String _buffer = '';

  SerialService({
    this.portName = '/dev/ttyACM0',
    this.baudRate = 115200,
    this.simulate = false,
  });

  /// Stream of parsed events from the Arduino (COIN, BILL, DISPENSE_DONE, ...).
  Stream<ArduinoEvent> get events => _eventController.stream;

  /// Stream of connection state (true = connected & receiving heartbeats).
  Stream<bool> get connectionState => _connectionController.stream;

  bool get isOpen => simulate ? true : (_port?.isOpen ?? false);

  /// Opens the serial port. Call once at app startup.
  /// Returns false if the port could not be opened (kiosk should show
  /// a "hardware unavailable" screen rather than crash).
  bool connect() {
    if (simulate) {
      _connectionController.add(true);
      return true;
    }
    try {
      final port = SerialPort(portName);
      if (!port.openReadWrite()) {
        _connectionController.add(false);
        return false;
      }
      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1;
      port.config = config;

      _port = port;
      _reader = SerialPortReader(port);
      _sub = _reader!.stream.listen(_onData, onError: (_) {
        _connectionController.add(false);
      });
      _connectionController.add(true);
      _startHeartbeatWatch();
      return true;
    } catch (_) {
      _connectionController.add(false);
      return false;
    }
  }

  void _onData(Uint8List chunk) {
    _buffer += utf8.decode(chunk, allowMalformed: true);
    var idx = _buffer.indexOf('\n');
    while (idx != -1) {
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (line.isNotEmpty) {
        final event = ArduinoEvent.parse(line);
        if (event.type == 'HEARTBEAT') {
          _lastHeartbeat = DateTime.now();
        }
        _eventController.add(event);
      }
      idx = _buffer.indexOf('\n');
    }
  }

  DateTime _lastHeartbeat = DateTime.now();
  Timer? _heartbeatTimer;

  void _startHeartbeatWatch() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final silentFor = DateTime.now().difference(_lastHeartbeat);
      if (silentFor > const Duration(seconds: 5) && isOpen) {
        _connectionController.add(false);
      }
    });
  }

  /// Sends a raw command line to the Arduino (newline appended automatically).
  void send(String command) {
    if (simulate) {
      // ignore: avoid_print
      print('[SIM] -> Arduino: $command');
      return;
    }
    final port = _port;
    if (port == null || !port.isOpen) return;
    port.write(Uint8List.fromList(utf8.encode('$command\n')));
  }

  // ── Simulation helpers (only meaningful when simulate == true) ───────────
  // Feed these from a debug panel to drive the exact same code path real
  // hardware events go through (KioskController._onArduinoEvent).

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
    _heartbeatTimer?.cancel();
    _sub?.cancel();
    _port?.close();
    _eventController.close();
    _connectionController.close();
  }
}

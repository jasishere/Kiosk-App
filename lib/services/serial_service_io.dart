import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../app_config.dart';
import 'arduino_protocol.dart';

export 'arduino_protocol.dart';

/// USB serial link to the Arduino Mega.
///
/// Three things this does that the previous version did not, all of which
/// were load-bearing for an unattended machine:
///
///  1. **Reconnects.** A USB re-enumeration (brownout, someone knocking the
///     cable) used to take the kiosk down until a human rebooted it. It now
///     retries on a timer and comes back on its own.
///  2. **Latches the link state.** The heartbeat watchdog used to re-emit
///     `false` once a second forever once the link went quiet. Every one of
///     those reached the controller, which logged an alert to Firestore —
///     an overnight fault would have written tens of thousands of alert
///     documents. State changes are now emitted on transition only.
///  3. **Tracks command acks.** [dispense] returns a Future that completes
///     when the Arduino confirms that specific hopper finished, or throws on
///     timeout. Fire-and-forget dispensing is how you end up marking a
///     transaction complete while notes are still moving.
class SerialService {
  final String portName;
  final int baudRate;

  SerialService({
    this.portName = AppConfig.serialPort,
    this.baudRate = AppConfig.serialBaud,
  });

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;
  Timer? _watchdog;
  Timer? _reconnect;

  final _events = StreamController<ArduinoEvent>.broadcast();
  final _link = StreamController<LinkState>.broadcast();

  String _buffer = '';
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  LinkState _state = LinkState.disconnected;
  bool _disposed = false;

  /// Outstanding dispense command awaiting its DISPENSE_DONE.
  _PendingDispense? _pending;

  Stream<ArduinoEvent> get events => _events.stream;

  /// Emits only on genuine transitions — never repeats the current state.
  Stream<LinkState> get link => _link.stream;

  LinkState get state => _state;
  bool get isConnected => _state == LinkState.connected;

  /// Opens the port and starts the watchdog. Safe to call repeatedly; it is
  /// also what the reconnect timer calls.
  bool connect() {
    if (_disposed) return false;
    if (_port?.isOpen ?? false) return true;

    _setState(LinkState.connecting);
    try {
      final port = SerialPort(portName);
      if (!port.openReadWrite()) {
        port.dispose();
        _scheduleReconnect();
        return false;
      }
      port.config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);

      _port = port;
      _reader = SerialPortReader(port);
      _sub = _reader!.stream.listen(
        _onData,
        onError: (Object e) {
          debugPrint('[serial] read error: $e');
          _dropLink();
        },
        onDone: _dropLink,
      );

      _lastHeartbeat = DateTime.now();
      _setState(LinkState.connected);
      _startWatchdog();
      send(ArduinoCommand.reset);
      return true;
    } catch (e) {
      debugPrint('[serial] open failed on $portName: $e');
      _scheduleReconnect();
      return false;
    }
  }

  void _setState(LinkState next) {
    if (_state == next || _disposed) return;
    _state = next;
    _link.add(next);
  }

  void _onData(Uint8List chunk) {
    _buffer += utf8.decode(chunk, allowMalformed: true);

    // Guard against a wedged device streaming bytes with no newline — an
    // unbounded buffer here is a slow memory leak on a machine expected to
    // run for months.
    if (_buffer.length > 8192) _buffer = _buffer.substring(_buffer.length - 1024);

    var idx = _buffer.indexOf('\n');
    while (idx != -1) {
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (line.isNotEmpty) _handleLine(line);
      idx = _buffer.indexOf('\n');
    }
  }

  void _handleLine(String line) {
    final event = ArduinoEvent.parse(line);

    // Any traffic at all proves the board is alive, not just HEARTBEAT —
    // a busy dispense cycle can legitimately delay the heartbeat.
    _lastHeartbeat = DateTime.now();
    if (_state == LinkState.stale) _setState(LinkState.connected);

    if (event.type == 'HEARTBEAT') return;

    if (event.type == 'DISPENSE_DONE' || event.type == 'DISPENSE_FAILED') {
      _resolvePending(event);
    }
    _events.add(event);
  }

  void _resolvePending(ArduinoEvent event) {
    final pending = _pending;
    if (pending == null) return;

    // Match on the echoed descriptor so a stale ack from a previous,
    // timed-out command can't complete the one currently in flight.
    final isBill = event.arg(0).toUpperCase() == 'BILL';
    final value = event.intArg(1);
    if (isBill != pending.isBill || value != pending.value) return;

    _pending = null;
    pending.timer.cancel();
    if (pending.completer.isCompleted) return;

    if (event.type == 'DISPENSE_FAILED') {
      pending.completer.completeError(
        DispenseException(
          'Hopper reported a fault dispensing ₱$value',
          dispensed: event.intArg(2),
        ),
      );
    } else {
      pending.completer.complete(event.intArg(2));
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != LinkState.connected) return;
      if (DateTime.now().difference(_lastHeartbeat) >
          AppConfig.heartbeatTimeout) {
        // Transition once. The old version re-emitted every tick.
        _setState(LinkState.stale);
        _dropLink();
      }
    });
  }

  void _dropLink() {
    _sub?.cancel();
    _sub = null;
    _reader = null;
    try {
      _port?.close();
      _port?.dispose();
    } catch (_) {
      // Port may already be gone — nothing useful to do.
    }
    _port = null;

    // Fail anything in flight rather than leaving the UI on a spinner.
    final pending = _pending;
    _pending = null;
    pending?.timer.cancel();
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(
        const DispenseException('Lost the link to the hardware mid-dispense'),
      );
    }

    _setState(LinkState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnect?.cancel();
    _reconnect = Timer(AppConfig.reconnectInterval, connect);
  }

  /// Writes a raw command line. Returns false if the port isn't open.
  bool send(String command) {
    final port = _port;
    if (port == null || !port.isOpen) return false;
    try {
      port.write(Uint8List.fromList(utf8.encode('$command\n')));
      return true;
    } catch (e) {
      debugPrint('[serial] write failed: $e');
      _dropLink();
      return false;
    }
  }

  /// Dispenses [count] units of one denomination and waits for the hopper to
  /// confirm. Completes with the number of units the Arduino reports it
  /// actually moved, or throws [DispenseException] on fault or timeout.
  ///
  /// One command in flight at a time by design: hoppers share a power rail,
  /// and running several at once both browns out the rail and makes a
  /// partial failure impossible to attribute to a denomination.
  Future<int> dispense({
    required int value,
    required bool isBill,
    required int count,
  }) {
    if (_pending != null) {
      return Future.error(
        const DispenseException('A dispense is already in progress'),
      );
    }
    if (!isConnected) {
      return Future.error(const DispenseException('Hardware is not connected'));
    }

    final completer = Completer<int>();
    final budget = AppConfig.dispenseBaseTimeout +
        AppConfig.dispensePerUnit * count;

    final pending = _PendingDispense(
      value: value,
      isBill: isBill,
      completer: completer,
      timer: Timer(budget, () {
        final p = _pending;
        if (p == null || p.completer != completer) return;
        _pending = null;
        if (!completer.isCompleted) {
          completer.completeError(
            DispenseException(
              'No confirmation from the ₱$value ${isBill ? 'note' : 'coin'} '
              'hopper within ${budget.inSeconds}s',
            ),
          );
        }
      }),
    );
    _pending = pending;

    if (!send(ArduinoCommand.dispense(value, isBill, count))) {
      _pending = null;
      pending.timer.cancel();
      return Future.error(
        const DispenseException('Could not write the dispense command'),
      );
    }
    return completer.future;
  }

  // Convenience wrappers — see docs/HARDWARE.md for the full table.
  void reset() => send(ArduinoCommand.reset);
  void uvOn() => send(ArduinoCommand.uvOn);
  void uvOff() => send(ArduinoCommand.uvOff);
  void captureAck() => send(ArduinoCommand.captureAck);
  void acceptBill() => send(ArduinoCommand.acceptBill);
  void rejectBill() => send(ArduinoCommand.rejectBill);
  void returnEscrow() => send(ArduinoCommand.returnEscrow);
  void enableAcceptors() => send(ArduinoCommand.acceptorEnable);
  void disableAcceptors() => send(ArduinoCommand.acceptorDisable);

  Future<void> dispose() async {
    _disposed = true;
    _watchdog?.cancel();
    _reconnect?.cancel();
    _pending?.timer.cancel();
    await _sub?.cancel();
    try {
      _port?.close();
      _port?.dispose();
    } catch (_) {}
    await _events.close();
    await _link.close();
  }
}

class _PendingDispense {
  final int value;
  final bool isBill;
  final Completer<int> completer;
  final Timer timer;

  _PendingDispense({
    required this.value,
    required this.isBill,
    required this.completer,
    required this.timer,
  });
}

/// Raised when a dispense cannot be confirmed. [dispensed] is how many units
/// the hardware believes it released before failing — the controller needs
/// it to reconcile inventory and to tell the customer what is in the tray.
class DispenseException implements Exception {
  final String message;
  final int dispensed;
  const DispenseException(this.message, {this.dispensed = 0});

  @override
  String toString() => message;
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../app_config.dart';
import 'arduino_protocol.dart';

export 'arduino_protocol.dart';

/// USB serial link to the Uno running `coinvert_firmware.ino`.
///
/// This firmware talks at **9600 baud** (`Serial.begin(9600)` in the .ino),
/// not 115200 — that's not a typo carried over from an earlier draft, it's
/// what this specific sketch actually opens the port at. If you change the
/// firmware's baud rate, change [baudRate]'s default here to match, or the
/// link will just produce garbled bytes with no clear error.
///
/// **This firmware has no confirmed-dispense count.** `dispense()` below
/// resolves as soon as a `DONE` line for the right lane arrives — that only
/// means the servo motion finished, not that a sensor verified units
/// actually left the compartment. Treat every successful `dispense()` result
/// as "commanded and the servo completed," not as "verified delivered."
/// [DispenseException] is still raised on a genuine timeout (no `DONE` at
/// all, e.g. the board hung or a wire came loose) — that part hasn't
/// changed — but there's no code path today where the firmware reports a
/// *partial* failure, because it doesn't have the sensor to notice one.
class SerialService {
  final String portName;
  final int baudRate;

  SerialService({
    this.portName = AppConfig.serialPort,
    this.baudRate = 9600,
  });

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;
  Timer? _reconnect;
  Timer? _pingWatchdog;

  final _events = StreamController<ArduinoEvent>.broadcast();
  final _link = StreamController<LinkState>.broadcast();

  String _buffer = '';
  LinkState _state = LinkState.disconnected;
  bool _disposed = false;
  DateTime _lastTraffic = DateTime.fromMillisecondsSinceEpoch(0);

  /// Outstanding dispense command awaiting its DONE line.
  _PendingDispense? _pending;

  Stream<ArduinoEvent> get events => _events.stream;
  Stream<LinkState> get link => _link.stream;
  LinkState get state => _state;
  bool get isConnected => _state == LinkState.connected;

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

      _lastTraffic = DateTime.now();
      _setState(LinkState.connected);
      _startPingWatchdog();
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
    _lastTraffic = DateTime.now();
    if (_state == LinkState.stale) _setState(LinkState.connected);

    final event = ArduinoEvent.parse(line);

    // This firmware has no heartbeat message — READY is sent once at boot,
    // and PONG only on request. Liveness is inferred from *any* traffic
    // (see _startPingWatchdog), not a dedicated heartbeat line.
    if (event.type == 'DISPENSE') {
      _resolvePending(event);
    }
    _events.add(event);
  }

  void _resolvePending(ArduinoEvent event) {
    // Wire shape: DISPENSE:<COIN|BILL>:DONE:<lane>
    // event.type == 'DISPENSE', args == [<COIN|BILL>, 'DONE', <lane>]
    if (event.args.length < 3) return;
    if (event.arg(1).toUpperCase() != 'DONE') return;

    final pending = _pending;
    if (pending == null) return;

    final isBill = event.arg(0).toUpperCase() == 'BILL';
    final lane = int.tryParse(event.arg(2)) ?? -1;
    if (isBill != pending.isBill || lane != pending.lane) return;

    _pending = null;
    pending.timer.cancel();
    if (!pending.completer.isCompleted) {
      // No confirmed-count field exists — resolve with the count that was
      // requested. See the class doc: this is "commanded," not "verified."
      pending.completer.complete(pending.requestedCount);
    }
  }

  /// This firmware sends no periodic heartbeat, so liveness is judged by
  /// "did anything at all arrive recently" and topped up with an explicit
  /// PING when it's been quiet — rather than assuming silence means death,
  /// which would false-trigger during a long dispense sequence where the
  /// board is busy running servos and not chatting.
  void _startPingWatchdog() {
    _pingWatchdog?.cancel();
    _pingWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_state != LinkState.connected) return;
      final quiet = DateTime.now().difference(_lastTraffic);
      if (quiet > AppConfig.heartbeatTimeout) {
        send(ArduinoCommand.ping);
        // One missed PING beyond a further grace period means genuinely gone.
        if (quiet > AppConfig.heartbeatTimeout * 2) {
          _setState(LinkState.stale);
          _dropLink();
        }
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
    } catch (_) {}
    _port = null;

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

  /// Dispenses [count] units of the coin or bill at lane [lane].
  ///
  /// Completes with [count] once the firmware reports that lane's servo
  /// sequence finished — again, that is not a verified count, see the class
  /// doc. Throws [DispenseException] if no `DONE` arrives within the
  /// timeout budget, or if the link drops mid-sequence.
  Future<int> dispenseAtLane({
    required int lane,
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
    // This firmware runs each unit's servo motion sequentially with fixed
    // delays (see BILL_SETTLE_MS / ROLLER_RUN_MS / COIN_SETTLE_MS in the
    // .ino) — the per-unit budget here must stay comfortably above the sum
    // of those, or the app will give up before the board finishes.
    final budget = AppConfig.dispenseBaseTimeout +
        AppConfig.dispensePerUnit * count;

    final pending = _PendingDispense(
      lane: lane,
      isBill: isBill,
      requestedCount: count,
      completer: completer,
      timer: Timer(budget, () {
        final p = _pending;
        if (p == null || p.completer != completer) return;
        _pending = null;
        if (!completer.isCompleted) {
          completer.completeError(
            DispenseException(
              'No confirmation from ${isBill ? 'bill' : 'coin'} lane $lane '
              'within ${budget.inSeconds}s',
            ),
          );
        }
      }),
    );
    _pending = pending;

    final command = isBill
        ? ArduinoCommand.dispenseBill(lane, count)
        : ArduinoCommand.dispenseCoin(lane, count);

    if (!send(command)) {
      _pending = null;
      pending.timer.cancel();
      return Future.error(
        const DispenseException('Could not write the dispense command'),
      );
    }
    return completer.future;
  }

  void acceptBill() => send(ArduinoCommand.billAccept);
  void rejectBill() => send(ArduinoCommand.billReject);
  void requestStatus() => send(ArduinoCommand.status);

  /// Gates the bill acceptor's own enable/inhibit line — see
  /// PIN_BILL_ACCEPTOR_ENABLE in the .ino. This is what makes it possible to
  /// actually refuse bills at the hardware level, rather than only being
  /// able to reject one after it's already been fed through and scanned.
  void enableAcceptor() => send(ArduinoCommand.acceptorOn);
  void disableAcceptor() => send(ArduinoCommand.acceptorOff);

  Future<void> dispose() async {
    _disposed = true;
    _pingWatchdog?.cancel();
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
  final int lane;
  final bool isBill;
  final int requestedCount;
  final Completer<int> completer;
  final Timer timer;

  _PendingDispense({
    required this.lane,
    required this.isBill,
    required this.requestedCount,
    required this.completer,
    required this.timer,
  });
}

/// Raised when a dispense cannot be confirmed at all (link loss, timeout).
/// [dispensed] is always 0 here — this firmware has no partial-progress
/// reporting, so there's nothing more specific to report than "it didn't
/// finish."
class DispenseException implements Exception {
  final String message;
  final int dispensed;
  const DispenseException(this.message, {this.dispensed = 0});

  @override
  String toString() => message;
}

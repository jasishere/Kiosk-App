import 'dart:async';

import '../app_config.dart';
import 'arduino_protocol.dart';

export 'arduino_protocol.dart';

/// Web build of [SerialService].
///
/// USB serial is not reachable from a browser, so this exists purely so the
/// project still analyses and builds for web tooling. It reports the link as
/// permanently disconnected, which puts the kiosk on its out-of-service
/// screen — the honest outcome, since a web build genuinely cannot run a
/// kiosk. The production target is Linux on the Raspberry Pi.
class SerialService {
  final String portName;
  final int baudRate;

  SerialService({
    this.portName = AppConfig.serialPort,
    this.baudRate = AppConfig.serialBaud,
  });

  final _events = StreamController<ArduinoEvent>.broadcast();
  final _link = StreamController<LinkState>.broadcast();

  Stream<ArduinoEvent> get events => _events.stream;
  Stream<LinkState> get link => _link.stream;

  LinkState get state => LinkState.disconnected;
  bool get isConnected => false;

  bool connect() {
    _link.add(LinkState.disconnected);
    return false;
  }

  bool send(String command) => false;

  Future<int> dispense({
    required int value,
    required bool isBill,
    required int count,
  }) =>
      Future.error(
        const DispenseException('Serial hardware is unavailable on web'),
      );

  void reset() {}
  void uvOn() {}
  void uvOff() {}
  void captureAck() {}
  void acceptBill() {}
  void rejectBill() {}
  void returnEscrow() {}
  void enableAcceptors() {}
  void disableAcceptors() {}

  Future<void> dispose() async {
    await _events.close();
    await _link.close();
  }
}

class DispenseException implements Exception {
  final String message;
  final int dispensed;
  const DispenseException(this.message, {this.dispensed = 0});

  @override
  String toString() => message;
}

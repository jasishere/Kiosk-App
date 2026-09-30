import 'dart:async';

import '../app_config.dart';
import 'arduino_protocol.dart';

export 'arduino_protocol.dart';

/// Web build stand-in. Browsers can't do USB serial, so this always reports
/// disconnected — the honest outcome, since a web build can't run a kiosk.
class SerialService {
  final String portName;
  final int baudRate;

  SerialService({
    this.portName = AppConfig.serialPort,
    this.baudRate = 9600,
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

  Future<int> dispenseAtLane({
    required int lane,
    required bool isBill,
    required int count,
  }) =>
      Future.error(
        const DispenseException('Serial hardware is unavailable on web'),
      );

  void acceptBill() {}
  void rejectBill() {}
  void requestStatus() {}
  void enableAcceptor() {}
  void disableAcceptor() {}

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

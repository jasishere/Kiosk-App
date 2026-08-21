// Platform switch: web can't use dart:ffi (flutter_libserialport needs it),
// so this file exports the ffi-free stub by default and swaps in the real
// serial implementation only when dart:io is available (desktop/mobile).
// Everything else in the app imports 'serial_service.dart' and never needs
// to know which one it got — both expose the same ArduinoEvent/SerialService API.
export 'serial_service_stub.dart'
    if (dart.library.io) 'serial_service_io.dart';

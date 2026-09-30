// Platform switch. The kiosk itself runs Linux on the Pi, which gets the
// real dart:ffi-backed implementation; the stub exists only so the project
// still analyses and builds under web tooling.
//
// Everything else in the app imports 'serial_service.dart' and never needs
// to know which one it got — both expose the same API surface.
export 'serial_service_stub.dart' if (dart.library.io) 'serial_service_io.dart';

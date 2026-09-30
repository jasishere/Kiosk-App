/// Deployment configuration.
///
/// Nothing here is hardcoded per-unit: every value comes from a
/// `--dart-define` at build time, so the same APK/bundle can be flashed to
/// every kiosk and pointed at a different `kiosks/{kioskId}` document.
///
///   flutter build linux --release \
///     --dart-define=KIOSK_ID=kiosk-01 \
///     --dart-define=SERIAL_PORT=/dev/ttyACM0 \
///     --dart-define=AI_BASE_URL=http://127.0.0.1:8000
///
/// KIOSK_ID must match a document created by the admin app's Kiosk Pairing
/// screen. It is a foreign key, not a free-form name.
class AppConfig {
  const AppConfig._();

  static const String kioskId =
      String.fromEnvironment('KIOSK_ID', defaultValue: 'kiosk-01');

  /// Firebase project identifiers (same values the web app uses; a Firebase
  /// web API key is an identifier, not a secret — access is governed by
  /// Firestore security rules).
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'coinvert-b1b8f',
  );

  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyCRo5V11u6qI0EzGZAusAmykpBff5t5BKU',
  );

  static const String serialPort =
      String.fromEnvironment('SERIAL_PORT', defaultValue: '/dev/ttyACM0');

  static const int serialBaud =
      int.fromEnvironment('SERIAL_BAUD', defaultValue: 115200);

  static const String aiBaseUrl = String.fromEnvironment('AI_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000');

  /// PIN for the on-site service panel (long-press the clock for 3s).
  /// Override per deployment; the default is deliberately not a real secret,
  /// it only gates a read-only diagnostics view.
  static const String servicePin =
      String.fromEnvironment('SERVICE_PIN', defaultValue: '246810');

  // ── Timings ───────────────────────────────────────────────────────────
  /// No customer input for this long mid-transaction → warn, then resolve.
  static const Duration idleWarning = Duration(seconds: 45);

  /// How long the warning stays up before the kiosk acts on it.
  static const Duration idleGrace = Duration(seconds: 15);

  /// Ceiling on a single dispense command, plus per-unit allowance. A
  /// hopper that hasn't acked within this is treated as jammed rather than
  /// left spinning forever.
  static const Duration dispenseBaseTimeout = Duration(seconds: 6);
  static const Duration dispensePerUnit = Duration(milliseconds: 1200);

  /// Arduino must emit HEARTBEAT more often than this or it's considered
  /// gone. Keep comfortably above the firmware's heartbeat interval.
  static const Duration heartbeatTimeout = Duration(seconds: 5);

  /// Delay between reconnect attempts after the serial link drops.
  static const Duration reconnectInterval = Duration(seconds: 3);

  /// How often to re-poll the Python AI service's /health endpoint.
  static const Duration aiHealthInterval = Duration(seconds: 30);

  /// Identical error codes are written to Firestore at most this often, so
  /// a stuck sensor can't generate thousands of alert documents overnight.
  static const Duration errorLogCooldown = Duration(minutes: 2);

  /// Complete screen auto-returns to Welcome after this.
  static const Duration completeAutoReturn = Duration(seconds: 25);
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result of an AI authentication call against the Python/OpenCV service.
class AuthResult {
  final bool authentic;
  final int? denomination;
  final double confidence;
  final String? errorMessage;

  AuthResult({
    required this.authentic,
    this.denomination,
    this.confidence = 0.0,
    this.errorMessage,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      authentic: json['authentic'] == true,
      denomination: json['denomination'] is int
          ? json['denomination'] as int
          : int.tryParse('${json['denomination']}'),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory AuthResult.error(String message) =>
      AuthResult(authentic: false, errorMessage: message);
}

/// Talks to a local Python service that wraps OpenCV/YOLOv8 banknote
/// authentication (per the thesis: Raspberry Pi 5 Camera V3 + 365nm UV LED
/// fluorescence capture, classified with YOLOv8 + OpenCV).
///
/// Why HTTP instead of calling Python directly from Dart: it keeps the ML
/// stack (Python, OpenCV, YOLO weights) completely decoupled from the UI.
/// You can develop/test/retrain the Python side independently, and swap
/// its internals without ever touching the Flutter app. The service is
/// expected to run on the same Raspberry Pi 5 as the kiosk UI, bound to
/// localhost only (not exposed on the network).
///
/// Minimal reference contract the Python service must implement:
///
///   POST http://127.0.0.1:8000/authenticate
///   -> triggers a capture from the already-active camera + UV LED and
///      runs the classifier on it (server holds the camera, not Flutter)
///   <- 200 OK
///      { "authentic": true, "denomination": 100, "confidence": 0.97 }
///
/// See python_reference/app.py in this project for a runnable stub.
class AiAuthService {
  final String baseUrl;
  final Duration timeout;

  /// When true, skips the HTTP call entirely and returns
  /// [nextSimulatedResult] (or a default authentic ₱100 result if unset).
  /// Set [nextSimulatedResult] from a debug panel before each simulated
  /// bill insert to test both the accept and reject/low-confidence paths.
  final bool simulate;
  AuthResult? nextSimulatedResult;

  AiAuthService({
    this.baseUrl = 'http://127.0.0.1:8000',
    this.timeout = const Duration(seconds: 8),
    this.simulate = false,
  });

  /// Triggers authentication of the currently staged banknote.
  /// Call this only after the Arduino reports `BILL_STAGED` and the
  /// Pi has sent `UV:ON` (see PROTOCOL.md sequence).
  Future<AuthResult> authenticate() async {
    if (simulate) {
      await Future.delayed(const Duration(milliseconds: 600)); // feels real
      final result = nextSimulatedResult ??
          AuthResult(authentic: true, denomination: 100, confidence: 0.97);
      nextSimulatedResult = null; // consume it
      return result;
    }
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/authenticate'))
          .timeout(timeout);

      if (response.statusCode != 200) {
        return AuthResult.error(
          'AI service returned HTTP ${response.statusCode}',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return AuthResult.fromJson(json);
    } on TimeoutException {
      return AuthResult.error('AI service timed out');
    } catch (e) {
      return AuthResult.error('AI service unreachable: $e');
    }
  }

  /// Simple health check — call at app startup so the kiosk can show a
  /// clear "authentication service offline" screen instead of hanging
  /// mid-transaction the first time someone inserts cash.
  Future<bool> healthCheck() async {
    if (simulate) return true;
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
